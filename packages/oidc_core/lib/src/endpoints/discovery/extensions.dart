import 'package:oidc_core/oidc_core.dart';

extension OidcProviderMetadataExt on OidcProviderMetadata {
  Uri selectAuthorizationEndpointByAuthorizationType(AuthorizationType type) {
    Uri? endpoint;
    switch (type) {
      case AuthorizationType.login:
        endpoint = authorizationEndpoint;
      case AuthorizationType.register:
        endpoint = registrationEndpoint;
    }
    if (endpoint == null) {
      throw OidcException(
        "The OpenId Provider doesn't provide the ${type == AuthorizationType.login ? OidcConstants_ProviderMetadata.authorizationEndpoint : OidcConstants_ProviderMetadata.registrationEndpoint}",
      );
    }
    return endpoint;
  }
}
