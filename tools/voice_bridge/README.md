# VIMO குரல் bridge (பதிப்பு 2) — Google Drive & இலவச Gemini

இந்த bridge உங்கள் சொந்த Google கணக்கில் இயங்கும் Apps Script. VIMO-வின் கற்றல் தரவு உங்கள் தனிப்பட்ட Drive-இல் மட்டுமே இருக்கும். **Access code இனி இல்லை**: ஒவ்வொரு கோரிக்கையும் உள்நுழைந்த நபரின் Firebase அடையாளத்துடன் வரும். அவர் உங்கள் ranch உறுப்பினரா என்பதை Firestore விதிகள் சரிபார்க்கும்.

## 1. ஒருமுறை அமைப்பு (iPhone Safari, “Request Desktop Website”)

1. [Google Apps Script](https://script.google.com/home) → பழைய VIMO project-ஐத் திறங்கள் (அல்லது **New project**).
2. [Code.gs](Code.gs) முழுவதையும் editor-இல் ஒட்டி Save.
3. **Project Settings → Show “appsscript.json” manifest file in editor** இயக்கி, [appsscript.json](appsscript.json) உள்ளடக்கத்தை ஒட்டி Save.
   இது கேட்கும் அனுமதிகள்: Drive-இல் **இந்த script உருவாக்கிய கோப்புகள் மட்டும்** (`drive.file`), வெளி இணைப்பு, Cloud billing/project-ஐ **படிக்க மட்டும்**.
4. **Project Settings → Script properties**:
   - `FIREBASE_PROJECT_ID` = `my-ranch-sync`
   - `FIREBASE_WEB_API_KEY` = VIMO app-இன் பொது Web API key (`lib/firebase_options.dart` → web `apiKey`; இது ரகசியம் அல்ல)
   - பழைய `VIMO_ACCESS_CODE` இருந்தால் **நீக்குங்கள்**.
5. Editor-இல் `setupVimoFolder` தேர்வு செய்து **Run**. Google அனுமதி கேட்கும் — உங்கள் கணக்கைத் தேர்ந்தெடுங்கள். உங்கள் Drive-இல் **VIMO AI** என்ற தனிப்பட்ட folder உருவாகும். அதை யாருடனும் share செய்ய வேண்டாம்; public ஆக்க வேண்டாம்.
6. **Triggers (கடிகாரக் குறி) → Add Trigger** → function `rebuildAliases`, event source **Time-driven**, **Day timer**. (மாட்டுப் பெயர் கற்றல் தினமும் தானாக நடக்கும்.)
7. **Deploy → Manage deployments → Edit (பென்சில்) → Version: New version → Deploy**. (புதிய deployment என்றால்: **Web app**, Execute as **Me**, Who has access **Anyone**.) `/exec` என முடியும் URL-ஐ நகலெடுங்கள்.
8. VIMO-வில் **Settings → VIMO குரல்** → URL ஒட்டி **Google Drive இணை**. “Google Drive இணைந்தது” வர வேண்டும்.

## 2. இலவச Gemini (விருப்பம்; இயல்பாக அணைந்திருக்கும்)

Gemini **மூன்றும்** இருந்தால் மட்டுமே அழைக்கப்படும்: (1) `GEMINI_ENABLED` = `true`, (2) அந்த நபர் VIMO குரல் திரையில் Gemini-ஐத் தேர்ந்தெடுத்தார், (3) ஒவ்வொரு அழைப்புக்கும் முன் project-இல் billing அணைந்துள்ளது என உறுதி. சந்தேகம் இருந்தால் ஒரு அழைப்பும் இல்லை.

1. [Google AI Studio → API keys](https://aistudio.google.com/api-keys) — **billing account இணைக்காத தனி project**-இல் key உருவாக்குங்கள். Card சேர்க்க வேண்டாம்.
2. அதே project-இல் [Cloud Console API Library](https://console.cloud.google.com/apis/library)-இல் **API Keys API**, **Cloud Resource Manager API**, **Cloud Billing API**, **Generative Language API** Enable.
3. Script properties: `GEMINI_PROJECT_ID`, `GEMINI_API_KEY` (key-ஐ **இங்கே மட்டும்** — chat-இலோ app-இலோ அல்ல), பிறகு `GEMINI_ENABLED` = `true`.
4. விருப்ப வரம்புகள்: `GEMINI_RANCH_DAILY` (இயல்பு 40), `GEMINI_GLOBAL_DAILY` (இயல்பு 150).

**உடனே அணைக்க:** `GEMINI_ENABLED`-ஐ நீக்குங்கள் (அல்லது `false`). Key-ஐ ரத்து செய்ய: AI Studio → API keys → அந்த key → Delete.
Model: `gemini-3.1-flash-lite` (2026-11-16 அன்று Free Tier விலைப் பக்கத்தில் சரிபார்த்தது). இலவச நிலையில் அனுப்பும் உரையை Google தன் சேவைகளை மேம்படுத்தப் பயன்படுத்தலாம் — அதனால் மாட்டுப் பெயர்கள் C1, C2 என மாற்றப்பட்டே அனுப்பப்படும்; ஒலி ஒருபோதும் அனுப்பப்படாது.

## 3. Drive-இல் என்ன இருக்கும்

```
VIMO AI/ranches/<மறைக்கப்பட்ட ranch பெயர்>/
  consent/        ஒவ்வொரு நபரின் ஒப்புதல்
  examples/       உறுதிசெய்த பால் வாக்கியங்கள் (மாற்ற முடியாத கோப்புகள்)
  audio-opt-in/   தனி ஒப்புதல் கொடுத்தவரின் குரல் மாதிரிகள் மட்டும்
  dictionaries/   கற்ற மாட்டுப் பெயர்ப் பதிப்புகள்
  active-manifest.json   செயலில் உள்ள பதிப்பு + checksum
```

சோதனை: `node tools/voice_bridge/bridge_test.cjs`
