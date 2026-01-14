import axios from "axios";

// Using relative path to leverage Nginx proxy
const API_URL = "/api";

export const api = axios.create({
    baseURL: API_URL,
});

export const setAuthToken = (user: any | null) => {
    if (user && user.token) {
        api.defaults.headers.common["Authorization"] = `Bearer ${user.token}`;
    } else {
        delete api.defaults.headers.common["Authorization"];
    }
};
