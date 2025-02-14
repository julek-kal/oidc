import 'package:oidc_core/oidc_core.dart';
import 'package:oidc_platform_interface/oidc_platform_interface.dart';

/// Helper class for flutter-based openid connect clients.
class OidcFlutter {
  static OidcPlatform get _platform => OidcPlatform.instance;

  /// Returns a stream that creates a hidden iframe every time you listen to it.
  ///
  /// The hidden iframe starts listening to session status if it's supported.
  static Stream<OidcMonitorSessionResult> monitorSessionStatus({
    required Uri checkSessionIframe,
    required OidcMonitorSessionStatusRequest request,
  }) =>
      _platform.monitorSessionStatus(
        checkSessionIframe: checkSessionIframe,
        request: request,
      );

  /// starts the authorization flow, and returns the response.
  ///
  /// on android/ios/macos, if the `request.responseType` is set to anything other than `code`, it returns null.
  ///
  /// NOTE: this DOES NOT do token exchange.
  ///
  /// consider using [OidcEndpoints.getProviderMetadata] to get the [metadata] parameter if you don't have it.
  static Future<OidcAuthorizeResponse?> getPlatformAuthorizationResponse({
    required OidcProviderMetadata metadata,
    required OidcAuthorizeRequest request,
    required AuthorizationType authorizationType,
    OidcPlatformSpecificOptions options = const OidcPlatformSpecificOptions(),
  }) async {
    try {
      return _platform.getAuthorizationResponse(
        metadata,
        authorizationType,
        request,
        options,
      );
    } on OidcException {
      rethrow;
    } catch (e, st) {
      throw OidcException(
        'Failed to authorize user',
        internalException: e,
        internalStackTrace: st,
      );
    }
  }

  /// starts the end session flow, and returns the response.
  ///
  /// consider using [OidcEndpoints.getProviderMetadata] to get the [metadata] parameter if you don't have it.
  static Future<OidcEndSessionResponse?> getPlatformEndSessionResponse({
    required OidcProviderMetadata metadata,
    required OidcEndSessionRequest request,
    OidcPlatformSpecificOptions options = const OidcPlatformSpecificOptions(),
  }) async {
    try {
      return _platform.getEndSessionResponse(
        metadata,
        request,
        options,
      );
    } catch (e, st) {
      throw OidcException(
        'Failed to end user session',
        internalException: e,
        internalStackTrace: st,
      );
    }
  }

  /// Listens to incoming front channel logout requests.
  ///
  /// [listenTo] parameter determines which path should be listened for to receive
  /// the request.
  ///
  /// on windows/linux/macosx this starts a server on the same prt
  static Stream<OidcFrontChannelLogoutIncomingRequest>
      listenToFrontChannelLogoutRequests({
    required Uri listenTo,
    OidcFrontChannelRequestListeningOptions options =
        const OidcFrontChannelRequestListeningOptions(),
  }) {
    return _platform.listenToFrontChannelLogoutRequests(listenTo, options);
  }
}
