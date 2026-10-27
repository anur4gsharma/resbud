# Resbud Manual Smoke-Test Guide

This guide describes the repeatable manual end-to-end verification procedure for the Resbud mobile client and local FastAPI backend. It covers the full 9-step vertical slice, error scenarios, and security/privacy verifications.

---

## 1. Prerequisites and Setup

### 1.1 Local Backend Setup

1. Open a terminal and navigate to `backend/`.
2. Ensure Python 3.12+ and `uv` (or the local virtualenv) are available.
3. Configure the local environment:
   ```bash
   cp ../.env.example .env
   ```
   Confirm `.env` includes:
   ```ini
   RESBUD_ENV=development
   RESBUD_GENERATION_PROVIDER=fake
   RESBUD_RATE_LIMIT_PER_MINUTE=60
   ```
4. Start the backend with hot reload:
   ```bash
   uv run uvicorn resbud_api.main:app --host 0.0.0.0 --port 8000 --reload
   ```
   *(Or with the local virtualenv: `.venv/bin/uvicorn resbud_api.main:app --host 0.0.0.0 --port 8000 --reload`)*
5. Verify health check in browser or curl:
   ```bash
   curl http://127.0.0.1:8000/health/live
   # Expected: {"status":"alive"}
   curl http://127.0.0.1:8000/health/ready
   # Expected: {"status":"ready","provider":"fake","environment":"development"}
   ```

### 1.2 Mobile Client Setup

#### Networking Note
- **Android Emulator**: The host machine's loopback interface (`127.0.0.1`) is reachable from the Android emulator at `http://10.0.2.2:8000`.
- **Physical Android Device**: Connect via USB with `adb reverse tcp:8000 tcp:8000`, or set the backend URL to your host's LAN IP (e.g., `http://192.168.1.X:8000`).
- **Desktop (Linux/macOS/Windows) / Chrome**: Connect directly via `http://127.0.0.1:8000`.

#### Launching the App
1. Navigate to `mobile/`.
2. Fetch dependencies:
   ```bash
   flutter pub get
   ```
3. Run on your target device or emulator:
   ```bash
   # Android emulator:
   flutter run -d emulator-5554

   # Or Chrome (web):
   flutter run -d chrome

   # Or Linux desktop:
   flutter run -d linux
   ```

---

## 2. Nine-Step Vertical Slice Smoke Test

Follow these steps sequentially to verify the complete product workflow.

### Step 1: Create a Local Project
- **Action**: On the empty Project List page, tap the `+` Floating Action Button (or "Create Project" button).
- **Inputs**:
  - Title: `Graph Neural Networks for Quantum Chemistry`
  - Field: `Computer Science`
- **Expected Outcome**:
  - Tapping "Create" navigates to the Project Input page.
  - The project title appears in the top AppBar.
  - Navigating back to the Project List shows the newly created project with creation timestamp and "No draft generated yet".

### Step 2: Enter Structured Research Details and Source Draft
- **Action**: Open the project and enter research context:
  - **Research Question**: `Can equivariant message passing predict molecular ground-state energies within chemical accuracy?`
  - **Objectives**: `1. Benchmark equivariant MPNNs against standard DFT. 2. Measure inference latency per conformer.`
  - **Contribution**: `A lightweight equivariant architecture achieving DFT accuracy with 10x lower inference cost.`
  - **Method**: Set status dropdown to `Provided`. Description: `Equivariant message passing on 3D Euclidean coordinates with spherical harmonics edge filters.`
  - **Dataset / Materials**: Set status dropdown to `Provided`. Description: `QM9 benchmark dataset consisting of 134k organic molecules.`
  - **Results**: Set status dropdown to `Explicitly Not Conducted / Unavailable`. (Verify that this radio/option is clearly distinct from "Unknown").
  - **Source Draft**: Enter text (>50 characters) or tap **"Import Document"** to select a `.txt` or `.docx` file.
- **Expected Outcome**:
  - If importing a document, document content populates the source draft field without clearing project metadata.
  - Characters count updates in real-time.

### Step 3: Review Missing Information Before Generation
- **Action**: Inspect the "Pre-generation Review & Integrity Warnings" section.
- **Expected Outcome**:
  - The app displays an amber warning card: `Results explicitly marked as not conducted`.
  - The integrity notice clarifies: `Output paper will omit fabricated empirical numbers and place verification markers where claims lack empirical backing.`
  - Tap **"Save Project & Context"**; verify a confirmation message appears and changes persist.

### Step 4: Submit to Backend Using Fake Provider
- **Action**: Tap **"Generate Paper Draft"**.
- **Expected Outcome**:
  - A loading indicator is displayed.
  - The generation button is disabled to prevent accidental duplicate submissions.
  - The app submits the structured request to `/api/v1/generations`.
  - Upon receiving the validated `PaperDraft` response, the app automatically transitions to the **Paper Editor** page.
  - The editor displays all standard sections in order:
    1. Title
    2. Abstract
    3. Introduction
    4. Method
    5. Results and Discussion
    6. Conclusion
    7. References
  - Warnings banner displays pre-generation review flags (e.g. `MISSING_RESULTS`).

### Step 5: Inspect Paper, Edit a Section, and Persist Edit
- **Action**:
  - Locate the **Introduction** section.
  - Tap the edit icon (or section card).
  - Modify the text by appending: `\n\n[Author Note: Verified against 2026 quantum baseline.]`
  - Tap **"Save Edit"**.
- **Expected Outcome**:
  - The updated text immediately reflects in the Introduction section.
  - A new local version entry (`Version 2`) is saved to SQLite with label `Manual Edit: Introduction`.
  - A brief confirmation notification confirms changes were saved.

### Step 6: Section Replacement Preview, Reject, and Accept
- **Action 6A (Preview & Reject)**:
  - Locate the **Method** section. Tap **"Regenerate Section"**.
  - Provide guidance prompt: `Emphasize message passing filter implementation details.`
  - Tap **"Request Preview"**.
  - Observe the bottom sheet / preview dialog displaying:
    - Current text
    - Proposed new text
  - Tap **"Reject Replacement"**.
  - **Verify**: The Method section remains byte-for-byte unchanged.
- **Action 6B (Regenerate & Accept)**:
  - Tap **"Regenerate Section"** on **Method** again.
  - Tap **"Request Preview"** -> **"Accept Replacement"**.
  - **Verify**:
    - The Method section is updated with the regenerated content.
    - **Crucial Check**: Verify that the **Introduction** section still contains `[Author Note: Verified against 2026 quantum baseline.]` and has NOT been overwritten or reset. All other sections remain intact.

### Step 7: Close and Reopen Project (Persistence & Versions)
- **Action**:
  - Tap the back button to return to the Project List.
  - Force-close / kill the mobile application process (or restart `flutter run`).
  - Relaunch the app. Tap on `Graph Neural Networks for Quantum Chemistry`.
- **Expected Outcome**:
  - The project title, metadata, source draft, and latest paper draft load immediately from local SQLite.
  - Open the **Version History** sheet/tab:
    - `v1`: Initial Generation
    - `v2`: Manual Edit: Introduction
    - `v3`: Regenerated Section: Method
  - Tapping a previous version allows previewing or restoring that exact snapshot.

### Step 8: Export Paper to DOCX and Inspect
- **Action**:
  - In the Paper Editor, tap **"Export to DOCX"** in the top AppBar.
  - Choose a destination or confirm the default exported file path.
- **Expected Outcome**:
  - The app sends the latest draft to `/api/v1/exports/docx`.
  - The backend generates a validated `.docx` binary and returns it with `Content-Type: application/vnd.openxmlformats-officedocument.wordprocessingml.document`.
  - The mobile app saves the file locally and displays the full file path.
  - Open the exported file in LibreOffice Writer, Microsoft Word, or Google Docs:
    - Document title is formatted as Heading 1 / Title.
    - Sections (Abstract, Introduction, Method, Results, Conclusion, References) are formatted with distinct Heading 2 styles and clean body paragraphs.
    - Numbered references appear in order without missing markers.

### Step 9: Fault Simulation and Resilience Verification
- **Test 9A: Backend Offline / Network Failure**:
  - Stop the backend server (`Ctrl+C` in the backend terminal).
  - In the app, tap "Regenerate Section".
  - **Verify**: A non-crashing error notification appears (`Cannot connect to generation server. Please check your network connection and server status.`).
  - **Verify**: The current paper content is completely preserved.
- **Test 9B: Malformed / Timeout / Request Oversize**:
  - Restart the backend.
  - In project inputs, attempt to submit a draft exceeding 50,000 characters.
  - **Verify**: Client-side form validation blocks the request before any network transmission.
- **Test 9C: Export Failure Resilience**:
  - Simulate an export failure (e.g. read-only file directory or temporary network drop).
  - **Verify**: Export error is presented gracefully; no saved version in SQLite is modified or deleted.

---

## 3. Security and Privacy Manual Verification

1. **Server Log Inspection**:
   - In the terminal running `uvicorn`, inspect the request logs during generation and section regeneration.
   - **Verify**:
     - Request lines show only metadata: `POST /api/v1/generations 200 OK duration=... request_id=...`
     - Neither the source draft, research question, user-authored notes, nor generated paper text appear anywhere in standard output or error logs.
2. **Mobile Bundle Secret Inspection**:
   - Run:
     ```bash
     grep -rn "sk-" mobile/
     grep -rn "API_KEY" mobile/lib/
     ```
   - **Verify**: Zero provider API keys or bearer secrets exist in client code.
3. **Fail-Closed Production Check**:
   - Start backend with `RESBUD_ENV=production` and `RESBUD_GENERATION_PROVIDER=fake`.
   - **Verify**: The application raises a startup error and refuses to run with a fake provider in production mode.

---

## 4. Untested Paths and Environment Limitations

1. **Physical Mobile Hardware Factors**:
   - The automated CI test suite uses the headless Flutter desktop/test runner and SQLite in-memory / temporary databases (`sqflite_common_ffi`).
   - Testing native Android permissions (e.g. Storage Access Framework on Android 13+) and physical back-gesture handling requires an interactive device or emulator.
2. **Live LLM Cost and Rate Limits**:
   - Routine automated tests and this smoke test run against the deterministic `FakeProvider`.
   - Live testing against OpenAI (`RESBUD_GENERATION_PROVIDER=openai`) requires an active internet connection, a valid OpenAI API key with credit balance, and will incur per-token API costs.
3. **Background Process Termination**:
   - OS-initiated process death (when Android OS reclaims memory while the app is in the background) relies on SQLite transaction safety, which is tested in unit tests, but deep OS lifecycle restoration was verified via normal app restarts rather than developer-options "Don't keep activities".
