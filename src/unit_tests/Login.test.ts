/// RESET PASSWORD TESTS ////

global.fetch = jest.fn();

describe("reset password", () => {

    beforeEach(() => {
        jest.clearAllMocks();
    });

    // -------------------------
    // 1. SUCCESS CASE
    // -------------------------

    it("resets password successfully", async () => {

        (fetch as any).mockResolvedValue({
            ok: true,
            json: async () => ({}),
        });

        const setSuccess = jest.fn();
        const setErrorMsg = jest.fn();
        const setIsLoading = jest.fn();

        await resetPassword({
            token: "abc",
            newPassword: "newpass",
            setSuccess,
            setErrorMsg,
            setIsLoading,
        });

        expect(setSuccess).toHaveBeenCalledWith(true);
        expect(setErrorMsg).not.toHaveBeenCalled();
        expect(setIsLoading).toHaveBeenCalledWith(false);
    });

    // -------------------------
    // 2. API ERROR CASE
    // -------------------------

    it("handles API error response", async () => {

        (fetch as any).mockResolvedValue({
            ok: false,
            json: async () => ({
                error: "Invalid token",
            }),
        });

        const setErrorMsg = jest.fn();

        await resetPassword({
            token: "abc",
            newPassword: "newpass",
            setSuccess: jest.fn(),
            setErrorMsg,
            setIsLoading: jest.fn(),
        });

        expect(setErrorMsg).toHaveBeenCalledWith("Invalid token");
    });

    // -------------------------
    // 3. DEFAULT ERROR MESSAGE
    // -------------------------

    it("uses fallback error message", async () => {

        (fetch as any).mockResolvedValue({
            ok: false,
            json: async () => ({}),
        });

        const setErrorMsg = jest.fn();

        await resetPassword({
            token: "abc",
            newPassword: "newpass",
            setSuccess: jest.fn(),
            setErrorMsg,
            setIsLoading: jest.fn(),
        });

        expect(setErrorMsg).toHaveBeenCalledWith(
            "Reset failed. The link may have expired."
        );
    });

    // -------------------------
    // 4. NETWORK ERROR
    // -------------------------

    it("handles network failure", async () => {

        (fetch as any).mockRejectedValue(new Error("Could not reach server"));

        const setErrorMsg = jest.fn();

        await resetPassword({
            token: "abc",
            newPassword: "newpass",
            setSuccess: jest.fn(),
            setErrorMsg,
            setIsLoading: jest.fn(),
        });

        expect(setErrorMsg).toHaveBeenCalledWith(
            "Could not reach the server."
        );
    });

});

async function resetPassword({
    token,
    newPassword,
    setSuccess,
    setErrorMsg,
    setIsLoading,
}) {
    try {
        const res = await fetch(`/resetpassword`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ token, newPassword }),
        });

        const data = await res.json();

        if (!res.ok) {
            setErrorMsg(
                data.error || "Reset failed. The link may have expired."
            );
            return;
        }

        setSuccess(true);

    } catch {
        setErrorMsg("Could not reach the server.");
    } finally {
        setIsLoading(false);
    }
}

/// AUTH LOGIN / SIGNUP TESTS ////

global.fetch = jest.fn();

describe("auth flow (login + signup)", () => {

    beforeEach(() => {
        jest.clearAllMocks();
        localStorage.clear();
    });

    // -------------------------
    // LOGIN SUCCESS
    // -------------------------

    it("logs in successfully", async () => {

        (fetch as any).mockResolvedValue({
            ok: true,
            json: async () => ({
                accessToken: "jwt-123",
            }),
        });

        const setIsAuthenticated = jest.fn();
        const setErrorMsg = jest.fn();
        const setIsLoading = jest.fn();

        await authFlow({
            view: "login",
            email: "test@mail.com",
            password: "pass",
            firstName: "",
            lastName: "",
            setIsAuthenticated,
            setShowVerifyModal: jest.fn(),
            setErrorMsg,
            setIsLoading,
        });

        expect(setIsAuthenticated).toHaveBeenCalledWith(true);
    });
    
    // -------------------------
    // LOGIN ERROR
    // -------------------------

    it("handles login failure", async () => {

        (fetch as any).mockResolvedValue({
            ok: false,
            json: async () => ({
                error: "Invalid credentials",
            }),
        });

        const setErrorMsg = jest.fn();

        await authFlow({
            view: "login",
            email: "test@mail.com",
            password: "wrong",
            firstName: "",
            lastName: "",
            setIsAuthenticated: jest.fn(),
            setShowVerifyModal: jest.fn(),
            setErrorMsg,
            setIsLoading: jest.fn(),
        });

        expect(setErrorMsg).toHaveBeenCalledWith("Invalid credentials");
    });

    // -------------------------
    // SIGNUP SUCCESS
    // -------------------------

    it("signs up successfully", async () => {

        (fetch as any).mockResolvedValue({
            ok: true,
            json: async () => ({}),
        });

        const setShowVerifyModal = jest.fn();

        await authFlow({
            view: "signup",
            firstName: "A",
            lastName: "B",
            email: "test@mail.com",
            password: "pass",
            setShowVerifyModal,
            setErrorMsg: jest.fn(),
            setIsLoading: jest.fn(),
            setIsAuthenticated: jest.fn(),
        });

        expect(setShowVerifyModal).toHaveBeenCalledWith(true);
    });

    // -------------------------
    // SIGNUP ERROR
    // -------------------------

    it("handles signup failure", async () => {

        (fetch as any).mockResolvedValue({
            ok: false,
            json: async () => ({
                error: "Email already exists",
            }),
        });

        const setErrorMsg = jest.fn();

        await authFlow({
            view: "signup",
            firstName: "A",
            lastName: "B",
            email: "test@mail.com",
            password: "pass",
            setErrorMsg,
            setIsLoading: jest.fn(),
            setIsAuthenticated: jest.fn(),
            setShowVerifyModal: jest.fn(),
        });

        expect(setErrorMsg).toHaveBeenCalledWith("Email already exists");
    });

});


/// FORGOT PASSWORD TESTS ////

global.fetch = jest.fn();

describe("forgot password", () => {

    beforeEach(() => {
        jest.clearAllMocks();
    });

    // -------------------------
    // SUCCESS
    // -------------------------

    it("sends forgot password email successfully", async () => {

        (fetch as any).mockResolvedValue({
            ok: true,
            json: async () => ({}),
        });

        const setShowForgotSentModal = jest.fn();
        const setErrorMsg = jest.fn();

        await forgotPassword({
            forgotEmail: "test@mail.com",
            setShowForgotSentModal,
            setErrorMsg,
            setIsLoading: jest.fn(),
        });

        expect(setShowForgotSentModal).toHaveBeenCalledWith(true);
    });

    // -------------------------
    // API ERROR
    // -------------------------

    it("handles API error", async () => {

        (fetch as any).mockResolvedValue({
            ok: false,
            json: async () => ({
                error: "User not found",
            }),
        });

        const setErrorMsg = jest.fn();

        await forgotPassword({
            forgotEmail: "test@mail.com",
            setShowForgotSentModal: jest.fn(),
            setErrorMsg,
            setIsLoading: jest.fn(),
        });

        expect(setErrorMsg).toHaveBeenCalledWith("User not found");
    });

    // -------------------------
    // NETWORK ERROR
    // -------------------------

    it("handles network failure", async () => {

        (fetch as any).mockRejectedValue(new Error("Network down"));

        const setErrorMsg = jest.fn();

        await forgotPassword({
            forgotEmail: "test@mail.com",
            setShowForgotSentModal: jest.fn(),
            setErrorMsg,
            setIsLoading: jest.fn(),
        });

        expect(setErrorMsg).toHaveBeenCalledWith("Could not reach the server.");
    });

});

export async function authFlow({
    view,
    email,
    password,
    firstName,
    lastName,
    setIsAuthenticated,
    setShowVerifyModal,
    setErrorMsg,
    setIsLoading,
}) {
    try {
        if (view === "login") {
            const res = await fetch(`/login`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ login: email, password }),
            });

            const data = await res.json();

            if (!res.ok) {
                setErrorMsg(data.error || "Login failed.");
                return;
            }

            localStorage.setItem("jwtToken", data.accessToken ?? "");
            setIsAuthenticated(true);

        } else {
            const res = await fetch(`/signup`, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ firstName, lastName, email, password }),
            });

            if (!res.ok) {
                const data = await res.json();
                setErrorMsg(data.error || "Registration failed.");
                return;
            }

            setShowVerifyModal(true);
        }

    } catch {
        setErrorMsg("Could not reach the server.");
    } finally {
        setIsLoading(false);
    }
}

export async function forgotPassword({
    forgotEmail,
    setShowForgotSentModal,
    setErrorMsg,
    setIsLoading,
}) {
    try {
        const res = await fetch(`/forgotpassword`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ email: forgotEmail }),
        });

        if (!res.ok) {
            const data = await res.json();
            setErrorMsg(data.error || "Something went wrong.");
            return;
        }

        setShowForgotSentModal(true);

    } catch {
        setErrorMsg("Could not reach the server.");
    } finally {
        setIsLoading(false);
    }
}

const localStorageMock = (() => {
    let store: Record<string, string> = {};

    return {
        getItem: jest.fn((key: string) => store[key] || null),
        setItem: jest.fn((key: string, value: string) => {
            store[key] = value;
        }),
        removeItem: jest.fn((key: string) => {
            delete store[key];
        }),
        clear: jest.fn(() => {
            store = {};
        }),
    };
})();

global.localStorage = localStorageMock as any;

beforeEach(() => {
    jest.clearAllMocks();
    localStorage.clear(); // ✅ works now
});
