// ignore_for_file: cascade_invocations, avoid_redundant_argument_values

import 'dart:async';
import 'dart:html';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:oidc_core/oidc_core.dart';
import 'package:oidc_platform_interface/oidc_platform_interface.dart';
import 'package:rxdart/rxdart.dart';
import 'package:url_launcher/url_launcher.dart';

final _logger = Logger('Oidc.OidcWeb');

/// The Web implementation of [OidcPlatform].
class OidcWeb extends OidcPlatform {
  /// Registers this class as the default instance of [OidcPlatform]
  static void registerWith([Object? registrar]) {
    OidcPlatform.instance = OidcWeb();
  }

  String _calculatePopupOptions(OidcPlatformSpecificOptions_Web web) {
    final h = web.popupHeight;
    final w = web.popupWidth;
    final top =
        (window.outerHeight - h) / 2 + (window.screen?.available.top ?? 0);
    final left =
        (window.outerWidth - w) / 2 + (window.screen?.available.left ?? 0);

    final windowOpts =
        'width=$w,height=$h,toolbar=no,location=no,directories=no,status=no,menubar=no,copyhistory=no&top=$top,left=$left';
    return windowOpts;
  }

  BodyElement _getBody() =>
      window.document.getElementsByTagName('body').first as BodyElement;
  IFrameElement _createHiddenIframe({
    required String iframeId,
    bool appendToDocument = true,
  }) {
    final prev = window.document.getElementById(iframeId);
    if (prev != null) {
      prev.remove();
    }
    final res = (window.document.createElement('iframe') as IFrameElement)
      ..id = iframeId
      ..width = '0'
      ..height = '0'
      ..hidden = true
      ..style.visibility = 'hidden'
      ..style.position = 'fixed'
      ..style.left = '-1000px'
      ..style.top = '0';
    if (appendToDocument) {
      final body = _getBody();
      body.append(res);
    }
    return res;
  }

  Future<Uri?> _getResponseUri({
    required OidcPlatformSpecificOptions_Web options,
    required Uri uri,
    required String? state,
  }) async {
    final channel = BroadcastChannel(options.broadcastChannel);
    final c = Completer<Uri>();
    final sub = channel.onMessage.listen((event) {
      final data = event.data;
      if (data is! String) {
        return;
      }
      final parsed = Uri.tryParse(data);
      if (parsed == null) {
        return;
      }

      if (state != null) {
        final (:parameters, responseMode: _) =
            OidcEndpoints.resolveAuthorizeResponseParameters(
          responseUri: parsed,
          resolveResponseModeByKey: OidcConstants_AuthParameters.state,
        );
        final incomingState = parameters[OidcConstants_AuthParameters.state];
        //if we give it a state, we expect it to be returned.
        if (incomingState != state) {
          //check for state mismatch.
          return;
        }
      }
      c.complete(parsed);
    });
    try {
      //first prepare
      switch (options.navigationMode) {
        case OidcPlatformSpecificOptions_Web_NavigationMode.samePage:
          //
          if (!await canLaunchUrl(uri)) {
            _logger.warning(
              "Couldn't launch the request url: $uri, this might be a false positive.",
            );
          }
          if (!await launchUrl(
            uri,
            webOnlyWindowName: '_self',
          )) {
            _logger.severe("Couldn't launch the request url: $uri");
          }
          // return null, since this mode can't be awaited.
          return null;
        case OidcPlatformSpecificOptions_Web_NavigationMode.newPage:
          //
          if (!await canLaunchUrl(uri)) {
            _logger.warning(
              "Couldn't launch the request url: $uri, this might be a false positive.",
            );
          }
          if (!await launchUrl(
            uri,
            webOnlyWindowName: '_blank',
          )) {
            _logger.severe("Couldn't launch the request url: $uri");
            return null;
          }
          //listen to response uri.
          return await c.future;
        case OidcPlatformSpecificOptions_Web_NavigationMode.popup:
          final windowOpts = _calculatePopupOptions(options);
          window.open(
            uri.toString(),
            'oidc_auth_popup',
            windowOpts,
          );
          return await c.future;
        case OidcPlatformSpecificOptions_Web_NavigationMode.hiddenIFrame:
          const iframeId = 'oidc-session-management-iframe';
          final iframe = _createHiddenIframe(
            iframeId: iframeId,
            appendToDocument: true,
          );
          iframe.src = uri.toString();
          final emptyUri = Uri();
          final res = await c.future.timeout(
            options.hiddenIframeTimeout,
            onTimeout: () => emptyUri,
          );
          iframe.remove();
          if (res == emptyUri) {
            return null;
          }
          return res;
      }
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<OidcAuthorizeResponse?> getAuthorizationResponse(
    OidcProviderMetadata metadata,
    AuthorizationType authorizationType,
    OidcAuthorizeRequest request,
    OidcPlatformSpecificOptions options,
  ) async {
    final endpoint = metadata
        .selectAuthorizationEndpointByAuthorizationType(authorizationType);
    final isNonePrompt =
        request.prompt?.contains(OidcConstants_AuthorizeRequest_Prompt.none) ??
            false;
    if (options.web.navigationMode ==
            OidcPlatformSpecificOptions_Web_NavigationMode.hiddenIFrame &&
        !isNonePrompt) {
      throw const OidcException(
        'hidden iframe can only be used with "none" prompt, '
        'since it prohibits user interaction',
      );
    }
    final respUri = await _getResponseUri(
      options: options.web,
      uri: request.generateUri(endpoint),
      state: request.state,
    );
    if (respUri == null) {
      return null;
    }
    return OidcEndpoints.parseAuthorizeResponse(
      responseUri: respUri,
      responseMode: request.responseMode,
    );
  }

  @override
  Future<OidcEndSessionResponse?> getEndSessionResponse(
    OidcProviderMetadata metadata,
    OidcEndSessionRequest request,
    OidcPlatformSpecificOptions options,
  ) async {
    final endpoint = metadata.endSessionEndpoint;
    if (endpoint == null) {
      throw const OidcException(
        "The OpenId Provider doesn't provide '${OidcConstants_ProviderMetadata.endSessionEndpoint}'.",
      );
    }

    final respUri = await _getResponseUri(
      options: options.web,
      uri: request.generateUri(endpoint),
      state: request.state,
    );
    if (respUri == null) {
      return null;
    }
    return OidcEndSessionResponse.fromJson(respUri.queryParameters);
  }

  @override
  Stream<OidcFrontChannelLogoutIncomingRequest>
      listenToFrontChannelLogoutRequests(
    Uri listenOn,
    OidcFrontChannelRequestListeningOptions options,
  ) {
    final logger = Logger('Oidc.OidcWeb.listenToFrontChannelLogoutRequests');
    final channel = BroadcastChannel(options.web.broadcastChannel);
    return channel.onMessage
        .map<OidcFrontChannelLogoutIncomingRequest?>((event) {
          final data = event.data;
          if (data is! String) {
            logger.finer('Received data: $data');
            return null;
          }
          final uri = Uri.tryParse(data);
          if (uri == null) {
            logger.finer('Parsed Received data: $uri');
            return null;
          }
          //listening on empty path, will listen on all paths.
          if (listenOn.pathSegments.isNotEmpty) {
            logger.finer(
              'listenOn has a path segment (${listenOn.path}), checking if it matches the input data.',
            );
            if (!listEquals(uri.pathSegments, listenOn.pathSegments)) {
              logger.finer(
                'listenOn has a different path segment (${listenOn.path}), than data (${uri.path}), '
                'skipping the event.',
              );
              // the paths don't match
              return null;
            }
          }
          if (listenOn.hasQuery) {
            logger.finer(
              'listenOn has a query segment (${listenOn.query}), checking if it matches the input data.',
            );
            // check if every queryParameter in listenOn is the same in uri
            if (!listenOn.queryParameters.entries.every(
              (element) => uri.queryParameters[element.key] == element.value,
            )) {
              logger.finer(
                'listenOn has a different query segment (${listenOn.query}), than data (${uri.query}), '
                'skipping the event.',
              );
              return null;
            }
          } else {
            logger.finer(
              'listenOn has NO query segment, checking if data contains requestType=front-channel-logout by default.',
            );
            //by default, if no query parameter exists, check that
            // requestType=front-channel-logout
            if (uri.queryParameters[OidcConstants_Store.requestType] !=
                OidcConstants_Store.frontChannelLogout) {
              logger.finer(
                'data has no requestType=front-channel-logout in its query segment (${uri.query}), '
                'skipping the event.',
              );
              return null;
            }
          }
          logger.fine('successfully matched data ($uri)');
          return OidcFrontChannelLogoutIncomingRequest.fromJson(
            uri.queryParameters,
          );
        })
        .whereNotNull()
        //close the broadcast channel when the user cancels the stream.
        .doOnCancel(channel.close);
  }

  @override
  Stream<OidcMonitorSessionResult> monitorSessionStatus({
    required Uri checkSessionIframe,
    required OidcMonitorSessionStatusRequest request,
  }) {
    StreamController<OidcMonitorSessionResult>? sc;
    StreamSubscription<int>? timerSub;
    StreamSubscription<MessageEvent>? messageSub;
    // Timer? timer;

    const iframeId = 'oidc-session-management-iframe';
    void onMessageReceived(Event event) {
      if (event is! MessageEvent) {
        return;
      }
      final streamController = sc;
      final iframe = document.getElementById(iframeId) as IFrameElement?;
      final eventOrigin = event.origin;
      if (iframe == null ||
          streamController == null ||
          eventOrigin != checkSessionIframe.origin) {
        _logger.warning(
          'ignoring received message; '
          'iframe is null ? ${iframe == null}; '
          'streamController is null ? ${streamController == null}; '
          'eventOrigin is: ($eventOrigin), should be equal to: (${checkSessionIframe.origin}).',
        );
        return;
      }
      final eventData = event.data;
      if (eventData is! String) {
        _logger.warning('Received iframe message was not a string: $eventData');
        return;
      }
      switch (eventData) {
        case 'error':
          _logger.warning('Received error iframe message');
          streamController.add(const OidcErrorMonitorSessionResult());
        case 'changed':
          _logger.fine('Received changed iframe message');
          streamController
              .add(const OidcValidMonitorSessionResult(changed: true));
        case 'unchanged':
          _logger.fine('Received unchanged iframe message');
          streamController
              .add(const OidcValidMonitorSessionResult(changed: false));
        default:
          _logger.warning('Received unknown iframe message: $eventData');
          streamController
              .add(OidcUnknownMonitorSessionResult(data: eventData));
      }
    }

    sc = StreamController<OidcMonitorSessionResult>(
      onListen: () async {
        final iframe =
            _createHiddenIframe(appendToDocument: false, iframeId: iframeId)
              ..id = iframeId
              ..src = checkSessionIframe.toString();
        final onloadFuture = iframe.onLoad.first;
        final body = _getBody();
        body.append(iframe);
        await onloadFuture;
        //start the session iframe
        messageSub = window.onMessage.listen(onMessageReceived);

        //send message to iframe
        await timerSub?.cancel();
        _logger.info('Starting periodic stream!');
        timerSub = Stream.periodic(
          request.interval,
          (computationCount) => computationCount,
        ).startWith(-1).listen((event) {
          final iframe = document.getElementById(iframeId);
          if (iframe is! IFrameElement) {
            return;
          }
          try {
            final cw = iframe.contentWindow;
            if (cw == null) {
              return;
            }
            const space = ' ';
            cw.postMessage(
              '${request.clientId}$space${request.sessionState}',
              checkSessionIframe.origin,
            );
          } catch (e, st) {
            timerSub?.cancel();
            _logger.severe("Failed to send postMessage to OP's iframe", e, st);
          }
        });
      },
      onCancel: () {
        //stop the session iframe
        timerSub?.cancel();
        messageSub?.cancel();
        document.getElementById(iframeId)?.remove();
      },
      onPause: () {
        timerSub?.pause();
      },
      onResume: () {
        timerSub?.resume();
      },
    );
    return sc.stream;
  }
}
