/// Generates the HTML login page for patient authentication.
///
/// The IAM server renders this page when the client app redirects to the
/// `/authorize` endpoint. The patient enters their credentials (patient ID
/// and date of birth) which are submitted back to `POST /authorize`.
///
/// All OAuth parameters are carried through as hidden form fields so the
/// authorization flow can continue after successful authentication.
func loginPageHTML(
    error: String? = nil,
    clientId: String,
    redirectURI: String,
    scope: String,
    state: String,
    codeChallenge: String,
    codeChallengeMethod: String
) -> String {
    let errorBlock: String
    if let error {
        errorBlock = """
                <div class="error">\(escapeHTML(error))</div>
            """
    } else {
        errorBlock = ""
    }

    return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Health Companion — Sign In</title>
            <style>
                * { box-sizing: border-box; margin: 0; padding: 0; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    background: #f5f5f7;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    min-height: 100vh;
                    padding: 20px;
                }
                .card {
                    background: white;
                    border-radius: 16px;
                    box-shadow: 0 4px 24px rgba(0,0,0,0.08);
                    padding: 40px 32px;
                    max-width: 400px;
                    width: 100%;
                }
                .icon {
                    text-align: center;
                    font-size: 48px;
                    margin-bottom: 16px;
                }
                h1 {
                    text-align: center;
                    font-size: 24px;
                    font-weight: 600;
                    margin-bottom: 8px;
                    color: #1d1d1f;
                }
                .subtitle {
                    text-align: center;
                    color: #86868b;
                    font-size: 14px;
                    margin-bottom: 24px;
                }
                label {
                    display: block;
                    font-size: 13px;
                    font-weight: 500;
                    color: #6e6e73;
                    margin-bottom: 4px;
                    margin-top: 16px;
                }
                input[type="text"], input[type="date"] {
                    width: 100%;
                    padding: 10px 12px;
                    border: 1px solid #d2d2d7;
                    border-radius: 8px;
                    font-size: 16px;
                    outline: none;
                    transition: border-color 0.2s;
                }
                input:focus { border-color: #0071e3; }
                button {
                    width: 100%;
                    margin-top: 24px;
                    padding: 12px;
                    background: #0071e3;
                    color: white;
                    border: none;
                    border-radius: 10px;
                    font-size: 16px;
                    font-weight: 500;
                    cursor: pointer;
                    transition: background 0.2s;
                }
                button:hover { background: #0077ED; }
                button:active { background: #006edb; }
                .error {
                    background: #fff0f0;
                    border: 1px solid #ff3b30;
                    color: #ff3b30;
                    border-radius: 8px;
                    padding: 10px 12px;
                    font-size: 14px;
                    margin-bottom: 8px;
                }
                .hint {
                    text-align: center;
                    color: #86868b;
                    font-size: 12px;
                    margin-top: 16px;
                }
            </style>
        </head>
        <body>
            <div class="card">
                <div class="icon">🏥</div>
                <h1>Sign In</h1>
                <p class="subtitle">Enter your patient credentials to authorize Health Companion.</p>
                \(errorBlock)
                <form method="POST" action="/authorize">
                    <input type="hidden" name="client_id" value="\(escapeHTML(clientId))">
                    <input type="hidden" name="redirect_uri" value="\(escapeHTML(redirectURI))">
                    <input type="hidden" name="scope" value="\(escapeHTML(scope))">
                    <input type="hidden" name="state" value="\(escapeHTML(state))">
                    <input type="hidden" name="code_challenge" value="\(escapeHTML(codeChallenge))">
                    <input type="hidden" name="code_challenge_method" value="\(escapeHTML(codeChallengeMethod))">

                    <label for="patient_id">Patient ID</label>
                    <input type="text" id="patient_id" name="patient_id"
                           placeholder="Enter your patient ID" required autocomplete="off">

                    <label for="date_of_birth">Date of Birth</label>
                    <input type="date" id="date_of_birth" name="date_of_birth" required>

                    <button type="submit">Sign In</button>
                </form>
                <p class="hint">Your patient ID was provided by your healthcare practice.</p>
            </div>
        </body>
        </html>
        """
}

/// Escapes HTML special characters to prevent XSS.
private func escapeHTML(_ string: String) -> String {
    string
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}
