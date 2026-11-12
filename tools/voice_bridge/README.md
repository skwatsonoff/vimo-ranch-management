# VIMO கற்றல் அமைப்பு

## 1. Google Drive இணைப்பு

1. iPhone Safari-ல் [Google Drive](https://drive.google.com/) திறந்து உங்கள் Google கணக்கில் **VIMO AI** என்ற தனிப்பட்ட folder உருவாக்குங்கள். Folder link-ல் `/folders/`க்குப் பிறகு வரும் ID-ஐ நகலெடுங்கள்.
2. [Google Apps Script](https://script.google.com/home) திறந்து **New project** தேர்வு செய்யுங்கள். Safari-ல் தேவைப்பட்டால் பக்க மெனுவில் **Request Desktop Website** தேர்வு செய்யுங்கள். [Code.gs](Code.gs) கோப்பை editor-ல் ஒட்டுங்கள்.
3. **Project Settings → Show “appsscript.json” manifest file in editor** இயக்குங்கள். Editor-ல் [appsscript.json](appsscript.json) கோப்பின் உள்ளடக்கத்தை ஒட்டி Save செய்யுங்கள்.
4. **Project Settings → Script properties → Add script property** வழியாக `VIMO_DRIVE_FOLDER_ID` சேர்த்து folder ID-ஐ value ஆகக் கொடுங்கள். Editor-ல் `generateVimoAccessCode` தேர்வு செய்து **Run** தட்டுங்கள். உங்கள் Google கணக்கில் அனுமதி கொடுத்து, Script properties-ல் உருவான `VIMO_ACCESS_CODE` மதிப்பை நகலெடுங்கள்.
5. **Deploy → New deployment → Web app** தேர்வு செய்யுங்கள். **Execute as → Me**, **Who has access → Anyone** தேர்வு செய்து Deploy செய்யுங்கள். ஒவ்வொரு கோரிக்கைக்கும் access code தேவை. `/exec` என்று முடியும் Web app URL-ஐ நகலெடுங்கள்.
6. VIMO-வில் **Settings → Train VIMO → Train → Google Drive & Gemini** திறங்கள். URL மற்றும் access code-ஐ உள்ளிட்டு **Connect & sync** தட்டுங்கள். **Google Drive synced** என்ற செய்தி வர வேண்டும். Access code-ஐ உங்கள் VIMO app-ல் மட்டும் உள்ளிடுங்கள்.

புதிய திருத்தங்களும் உறுதிசெய்த மாட்டுப் பெயர் உதாரணங்களும் ஒத்திசையும். **Train VIMO → Data → Upload to Drive** வழியாக புதிய குரல் WAV கோப்புகளைத் தனியாகப் பதிவேற்றலாம்.

## 2. ₹0 Gemini

1. [Google AI Studio → API keys](https://aistudio.google.com/api-keys) திறக்கவும். Billing account இணைக்காத தனி **Free Tier** project-ல் API key உருவாக்குங்கள். அந்த project-ன் **Project ID**-ஐ எடுத்துக்கொள்ளுங்கள்.
2. அதே project-ஐ [Google Cloud Console](https://console.cloud.google.com/apis/library) இல் தேர்வு செய்து **API Keys API**, **Cloud Resource Manager API**, **Cloud Billing API**, **Generative Language API** ஆகியவற்றை Enable செய்யுங்கள். Billing account இணைக்கப்படாததைச் சரிபார்க்க இந்த API-கள் பயன்படும்.
3. Apps Script **Project Settings → Script properties** இல் `GEMINI_PROJECT_ID`, `GEMINI_API_KEY` சேர்க்கவும். API key-ஐ இங்கே மட்டும் உள்ளிடுங்கள். Apps Script இயக்கும் Google கணக்குக்கு அந்த Cloud project-ல் API key lookup மற்றும் project metadata read அனுமதி தேவை.
4. VIMO-வில் **Gemini Free Tier fallback → Connect & sync** தட்டுங்கள். Free Tier சரிபார்ப்பு வென்றால் switch இயங்கும். **Drive synced. Gemini Free Tier could not be verified** என்றால் Drive இணைப்பு வேலை செய்கிறது. Google Cloud project ID, key, API அனுமதிகளைச் சரிபாருங்கள்.

தெளிவான பால் கட்டளைகளுக்கு VIMO சாதனத்திலேயே பதிலளிக்கும். Gemini உதவியால் கிடைத்த மாடு அல்லது அளவை VIMO உங்களிடம் உறுதிசெய்யும். இலவச quota முடிந்தால் அல்லது இணையம் கிடைக்காவிட்டால் manual milk form திறக்கும்.

## 3. சொந்த குரல் மாடல்

**Settings → Train VIMO → Train → Train VIMO** நீங்கள் திருத்திய பால் கட்டளைகளிலிருந்து சாதனத்திலேயே மாட்டுப் பெயர் அறியும் மாடலை உருவாக்கும்.

தனி speech-recognition மாடலுக்கு **Record**-ல் உங்கள் இயல்பான தமிழிலும் Tanglish-லும் பல்வேறு மாட்டுப் பெயர்கள், லிட்டர் அளவுகள், சொல் வரிசைகளுடன் பதிவு செய்யுங்கள். **Data → Upload to Drive** தட்டிவிட்டு, [Colab notebook](https://colab.research.google.com/github/skwatsonoff/vimo-ranch-management/blob/main/tools/voice_training/finetune_asr_colab.ipynb) திறக்கவும். Drive-ல் WAV கோப்புகள் உள்ள folder path-ஐ உள்ளிட்டு, இலவச GPU கிடைக்கும்போது cells-ஐ வரிசையாக இயக்கவும். சோதனை அறிக்கையும், பிழை விகிதம் குறைந்தால் candidate model-உம் உங்கள் Drive-ல் இருக்கும். அந்த speech model-ஐ app-ல் பயன்படுத்தும் முன் iPhone-ல் தனியாகச் சோதிக்க வேண்டும்.
