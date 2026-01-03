import axios from "axios";
import { User } from "oidc-client-ts";

const API_URL = import.meta.env.VITE_API_URL || "http://localhost:8000";

export const api = axios.create({
    baseURL: API_URL,
});

export const setAuthToken = (user: User | null) => {
    if (user) {
        api.defaults.headers.common["Authorization"] = `Bearer ${user.access_token}`;
    } else {
        delete api.defaults.headers.common["Authorization"];
    }
};
