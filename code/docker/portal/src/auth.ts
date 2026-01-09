import { AuthProviderProps } from "react-oidc-context";
import { User } from "oidc-client-ts";

export const oidcConfig: AuthProviderProps = {
    authority: import.meta.env.VITE_KEYCLOAK_URL || "http://localhost:8081/realms/apollo11",
    client_id: "apollo11-portal",
    redirect_uri: window.location.origin + "/",
    onSigninCallback: (_user: User | void) => {
        window.history.replaceState({}, document.title, window.location.pathname);
    }
};
