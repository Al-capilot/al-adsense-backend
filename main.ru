import os
import math
import requests
from crewai import Agent, Task, Crew, Process
from crewai.tools import tool
from crewai_tools import SerperDevTool
from langchain_openai import ChatOpenAI
from moviepy.editor import AudioFileClip, VideoFileClip, concatenate_audioclips, concatenate_videoclips
from reportlab.lib.pagesizes import A4
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle

# ==========================================
# 1. API AÇARLARI VƏ MÜHİT DƏYƏRPƏLƏRİ
# ==========================================
os.environ["OPENAI_API_KEY"] = "SIZIN_OPENAI_API_ACARINIZ"
os.environ["SERPER_API_KEY"] = "SIZIN_SERPER_API_ACARINIZ"
ELEVENLABS_API_KEY = "SIZIN_ELEVENLABS_API_ACARINIZ"
VAPI_API_KEY = "SIZIN_VAPI_API_ACARINIZ"
WHATSAPP_TOKEN = "SIZIN_META_WHATSAPP_TOKEN"
WHATSAPP_PHONE_ID = "SIZIN_PHONE_NUMBER_ID"

# Peşəkar və səhvsiz nəticə üçün temperaturu aşağı saxlayırıq
llm_expert = ChatOpenAI(model="gpt-4o", temperature=0.2)

# ==========================================
# 2. XÜSUSİ ALƏTLƏR (TOOLS)
# ==========================================

# A) Google Axtarış Aləti
search_tool = SerperDevTool()

# B) WhatsApp Mesaj Göndərmək Aləti
@tool("WhatsApp Mesajı Göndər")
def whatsapp_mesaj_gonder(telefon_nomresi: str, mesaj_metni: str):
    """Göstərilən nömrəyə WhatsApp vasitəsilə avtomatik mətn mesajı göndərir."""
    url = f"https://graph.facebook.com/v17.0/{WHATSAPP_PHONE_ID}/messages"
    headers = {"Authorization": f"Bearer {WHATSAPP_TOKEN}", "Content-Type": "application/json"}
    payload = {
        "messaging_product": "whatsapp",
        "to": telefon_nomresi,
        "type": "text",
        "text": {"body": mesaj_metni}
    }
    try:
        response = requests.post(url, json=payload, headers=headers, timeout=15)
        return "WhatsApp mesajı uğurla göndərildi." if response.status_code == 200 else f"Xəta: {response.text}"
    except Exception as e:
        return f"Bağlantı xətası: {e}"

# C) Səsli Zəng Etmək Aləti (Vapi AI)
@tool("Müştəriyə Zəng Et")
def musteriye_zeng_et(telefon_nomresi: str, danisiq_metni: str):
    """Süni intellekt səsi ilə göstərilən nömrəyə zəng edir."""
    url = "https://api.vapi.ai/call"
    headers = {"Authorization": f"Bearer {VAPI_API_KEY}", "Content-Type": "application/json"}
    payload = {
        "phoneNumber": telefon_nomresi,
        "assistant": {
            "model": {"provider": "openai", "model": "gpt-4o"},
            "firstMessage": danisiq_metni
        }
    }
    try:
        response = requests.post(url, json=payload, headers=headers, timeout=15)
        return "Zəng uğurla başladıldı." if response.status_code == 201 else f"Zəng xətası: {response.text}"
    except Exception as e:
        return f"Zəng xətası: {e}"

# D) WordPress-ə Avtomatik Paylaşım Aləti (Draft statusu ilə təhlükəsiz)
@tool("WordPress Paylaşımı")
def wordpress_paylas(basliq: str, mezmun: str, status: str = "draft"):
    """Yaradılmış məqaləni WordPress saytına qaralama olaraq yükləyir."""
    wp_url = "https://sizin-sayt.com/wp-json/wp/v2/posts"
    auth = ("WP_ISTIFADECI_ADI", "WP_APPLICATION_PASSWORD")
    payload = {"title": basliq, "content": mezmun, "status": status}
    try:
        response = requests.post(wp_url, json=payload, auth=auth, timeout=15)
        return "Məqalə WordPress-ə qaralama olaraq əlavə edildi." if response.status_code == 201 else f"WP Xəta: {response.text}"
    except Exception as e:
        return f"WP Bağlantı xətası: {e}"

# E) PDF Hesabat Hazırlamaq Aləti
@tool("PDF Hesabat Yarat")
def pdf_hesabat_arat(fayl_adi: str, basliq: str, metin_mezmunu: str):
    """Sistem fəaliyyəti və ya məqalə üçün rəsmi PDF sənədi yaradır."""
    doc = SimpleDocTemplate(fayl_adi, pagesize=A4)
    styles = getSampleStyleSheet()
    elements = []
    
    title_style = ParagraphStyle(
        'TitleStyle',
        parent=styles['Heading1'],
        fontSize=18,
        spaceAfter=15
    )
    body_style = ParagraphStyle(
        'BodyStyle',
        parent=styles['Normal'],
        fontSize=11,
        leading=16,
        spaceAfter=10
    )
    
    elements.append(Paragraph(basliq, title_style))
    elements.append(Spacer(1, 10))
    elements.append(Paragraph(metin_mezmunu, body_style))
    
    doc.build(elements)
    return f"PDF hesabat uğurla yaradıldı: {fayl_adi}"


# ==========================================
# 3. UZUN VİDEO VƏ SƏS MONTAJI (MoviePy + ElevenLabs)
# ==========================================
def elevenlabs_seslendir(metn: str, output_path: str):
    url = "https://api.elevenlabs.io/v1/text-to-speech/21m00Tcm4TlvDq8ikWAM"
    headers = {"xi-api-key": ELEVENLABS_API_KEY, "Content-Type": "application/json"}
    payload = {"text": metn, "model_id": "eleven_multilingual_v2"}
    response = requests.post(url, json=payload, headers=headers)
    if response.status_code == 200:
        with open(output_path, "wb") as f:
            f.write(response.content)

def uzun_video_hazirla(skript_metni: str, background_video_path: str, output_video_path: str):
    chunk_size = 3500
    parcalar = [skript_metni[i:i+chunk_size] for i in range(0, len(skript_metni), chunk_size)]
    audio_fayllari = []
    
    for idx, parca in enumerate(parcalar):
        parca_adi = f"temp_audio_{idx}.mp3"
        elevenlabs_seslendir(parca, parca_adi)
        if os.path.exists(parca_adi):
            audio_fayllari.append(AudioFileClip(parca_adi))
            
    if not audio_fayllari:
        return None

    final_audio = concatenate_audioclips(audio_fayllari)
    toplam_sure = final_audio.duration

    video_clip = VideoFileClip(background_video_path)
    loop_sayi = math.ceil(toplam_sure / video_clip.duration)
    uzadilmis_video = concatenate_videoclips([video_clip] * loop_sayi)
    final_video = uzadilmis_video.subclip(0, toplam_sure)
    
    final_video = final_video.set_audio(final_audio)
    final_video.write_videofile(output_video_path, codec="libx264", audio_codec="aac", fps=24)
    return output_video_path


# ==========================================
# 4. PEŞƏKAR AGENTLƏRİN TƏYİN EDİLMƏSİ
# ==========================================
analitik_agent = Agent(
    role='Baş Qlobal Trend və Data Analitiki (Senior Lead)',
    goal='Google-da dərin axtarış apararaq ən yüksək CPM gətirən, yoxlanılmış və dayanıqlı maliyyə/AI mövzularını müəyyən etmək.',
    backstory='15 illik rəqəmsal marketinq və SEO təcrübəsinə malik baş analitikssən. Yalnız statistik olaraq sübut edilmiş, yüksək dəyərli və etibarlı trendləri seçməkdə ekspertsən.',
    tools=[search_tool],
    verbose=True,
    llm=llm_expert
)

yazi_agenti = Agent(
    role='Baş Redaktor və SEO Mütəxəssisi',
    goal='Google E-E-A-T qaydalarına tam uyğun, unikal, oxucu üçün real fayda verən və peşəkar dildə məqalələr yazmaq.',
    backstory='Nüfuzlu maliyyə jurnallarında baş redaktor işləmisən. Məlumatları strukturlaşdıraraq oxuyucunu yormayan, hüquqi xəbərdarlıqları daxil edən qüsursuz məqalələr yaradırsan.',
    tools=[wordpress_paylas, pdf_hesabat_arat],
    verbose=True,
    llm=llm_expert
)

kommunikasiya_agenti = Agent(
    role='Korporativ Əlaqələr və Dəstək Direktoru',
    goal='Müştərilərlə və tərəfdaşlarla yüksək səviyyəli biznes etikasına uyğun şəkildə ünsiyyət qurmaq, bildirişlər göndərmək.',
    backstory='Böyük şirkətlərdə müştəri təcrübəsi və korporativ kommunikasiya sahəsində 10 illik təcrübəsi olan peşəkar menecersən.',
    tools=[whatsapp_mesaj_gonder, musteriye_zeng_et],
    verbose=True,
    llm=llm_expert
)

# ==========================================
# 5. TAPŞIRIQULAR VƏ İŞ PROSESİ (CREW)
# ==========================================
trend_tapshirigi = Task(
    description='ABŞ və Avropada bu gün ən çox maraq doğuran 1 süni intellekt/maliyyə mövzusunu dərindən araşdır.',
    expected_output='Mövzu başlığı, əsas detallar və analitik xülasə.',
    agent=analitik_agent
)

yazi_tapshirigi = Task(
    description='Tapılan mövzu əsasında peşəkar məqalə yaz, WordPress-ə qaralama olaraq yüklə və PDF hesabat faylı yarat.',
    expected_output='Uğurlu WordPress və PDF yükləmə təsdiqi.',
    agent=yazi_agenti
)

# Komandanın işə salınması
ai_sistemi = Crew(
    agents=[analitik_agent, yazi_agenti, kommunikasiya_agenti],
    tasks=[trend_tapshirigi, yazi_tapshirigi],
    process=Process.sequential,
    verbose=True
)

if __name__ == "__main__":
    print("Peşəkar Multi-Agent Sistemi işə düşür...")
    # nəticə = ai_sistemi.kickoff()
    # print("Proses uğurla tamamlandı:", nəticə)
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.application import MIMEApplication
from crewai.tools import tool

@tool("Email Göndər")
def email_gonder(alici_email: str, movzu: str, mesaj_metni: str, pdf_yolu: str = None):
    """
    Göstərilən e-poçt ünvanına başlıq, mətn və istəyə bağlı olaraq PDF faylı əlavə edərək e-poçt göndərir.
    """
    gonderen_email = "sizin_email@gmail.com"
    gonderen_sifre = "sizin_gmail_app_password" # Gmail tətbiq şifrəsi
    
    msg = MIMEMultipart()
    msg['From'] = gonderen_email
    msg['To'] = alici_email
    msg['Subject'] = movzu
    
    # Mətn hissəsi
    msg.attach(MIMEText(mesaj_metni, 'plain'))
    
    # Əgər PDF hesabat varsa, onu da e-poçtə əlavə edirik
    if pdf_yolu and os.path.exists(pdf_yolu):
        with open(pdf_yolu, "rb") as f:
            pdf_attachment = MIMEApplication(f.read(), Name=os.path.basename(pdf_yolu))
            pdf_attachment['Content-Disposition'] = f'attachment; filename="{os.path.basename(pdf_yolu)}"'
            msg.attach(pdf_attachment)
            
    try:
        # Gmail SMTP serveri vasitəsilə göndərilmə
        server = smtplib.SMTP('smtp.gmail.com', 587)
        server.starttls()
        server.login(gonderen_email, gonderen_sifre)
        server.sendmail(gonderen_email, alici_email, msg.as_string())
        server.quit()
        return f"E-poçt uğurla göndərildi: {alici_email}"
    except Exception as e:
        return f"E-poçt göndərmə xətası: {e}"
