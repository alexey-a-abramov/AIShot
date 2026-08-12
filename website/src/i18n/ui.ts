export const languages = {
  en: 'English',
  fr: 'Français',
  es: 'Español',
} as const;

export type Lang = keyof typeof languages;
export const defaultLang: Lang = 'en';

interface Feature { title: string; desc: string; }
interface Tool { name: string; desc: string; }
interface Step { title: string; desc: string; }

interface Content {
  title: string;
  description: string;
  nav: { features: string; agents: string; how: string; privacy: string; download: string; github: string };
  hero: { badge: string; title: string; subtitle: string; ctaDownload: string; ctaGithub: string };
  featuresTitle: string;
  features: Feature[];
  agents: { title: string; body: string; toolsTitle: string; tools: Tool[]; gated: string };
  how: { title: string; steps: Step[] };
  privacy: { title: string; body: string; points: string[] };
  download: { title: string; requirements: string; reqItems: string[]; buildTitle: string };
  footer: { tagline: string; note: string };
}

export const ui: Record<Lang, Content> = {
  en: {
    title: 'AIShot — Native macOS screenshots for humans and AI agents',
    description: 'A modern macOS capture tool: region/window/display screenshots, annotation, OCR, recording — plus a local MCP server so AI agents can capture and act on your screen, all on-device.',
    nav: { features: 'Features', agents: 'For agents', how: 'How it works', privacy: 'Privacy', download: 'Download', github: 'GitHub' },
    hero: {
      badge: 'Native · macOS 15+ · Local-first',
      title: 'Screenshots built for humans and AI agents',
      subtitle: 'Capture, annotate, and recognize — then let local AI agents drive the same capabilities over a bundled MCP server. Nothing leaves your Mac.',
      ctaDownload: 'Get started',
      ctaGithub: 'View source',
    },
    featuresTitle: 'Everything you expect, and more',
    features: [
      { title: 'Region, window & display capture', desc: 'Retina-correct ScreenCaptureKit grabs with a fast selection overlay and self-timer.' },
      { title: 'Annotate', desc: 'Arrows, shapes, text, highlighter, numbered steps, and blur/pixelate redaction.' },
      { title: 'OCR text-grab', desc: 'Recognize text in any region and copy it straight to the clipboard.' },
      { title: 'Color picker & pin', desc: 'Pixel-accurate eyedropper with hex, and pin a shot on top of every window.' },
      { title: 'Beautify', desc: 'Frame a screenshot on a gradient with padding, rounded corners and shadow.' },
      { title: 'Auto-redact', desc: 'Detect and blur emails, card numbers and IPs automatically.' },
      { title: 'Screen recording', desc: 'Record a display to H.264 video or an animated GIF, straight to your save folder.' },
      { title: 'Scrolling capture', desc: 'Scroll and stitch long pages into one tall screenshot.' },
      { title: 'Search inside your screenshots', desc: 'Every capture is read with on-device OCR, so you can find one by the words it contains — not just its file name.' },
      { title: 'Notes, tags & dashboard', desc: 'Attach a note and project tag to any capture, then browse, multi-select, and manage them all in one window.' },
    ],
    agents: {
      title: 'Built for AI agents',
      body: 'AIShot embeds a Model Context Protocol (MCP) server so local agents like Claude Code can see and act on your screen — on-device, with no cloud round-trip. Capture and read tools are always available; tools that move the mouse or type are confirmation-gated.',
      toolsTitle: 'MCP tools',
      tools: [
        { name: 'capture_region / capture_window / capture_display', desc: 'Capture and return the image plus metadata.' },
        { name: 'list_displays / list_windows / list_apps', desc: 'Enumerate what is on screen.' },
        { name: 'ocr', desc: 'Recognize text in a display or region.' },
        { name: 'search_captures', desc: 'Find past captures by the text inside them, or by note, tag, or file name.' },
        { name: 'get_history', desc: 'List recent captures.' },
        { name: 'annotate / beautify / redact', desc: 'Transform images programmatically.' },
        { name: 'locate', desc: 'Find on-screen UI by text and return rects.' },
        { name: 'switch_app / click / type_text', desc: 'Drive other apps — confirmation-gated.' },
      ],
      gated: 'The server talks to your agent over stdio and opens no network socket. Input tools stay refused until you explicitly opt in.',
    },
    how: {
      title: 'How it works',
      steps: [
        { title: 'Grant permissions', desc: 'Screen Recording for capture, Accessibility for agent input.' },
        { title: 'Capture', desc: 'Use a global hotkey or the menu bar to grab region, window, or display.' },
        { title: 'Edit & share', desc: 'Annotate, beautify, copy to clipboard, or save with a custom name.' },
        { title: 'Connect agents', desc: 'Enable the server in Settings, point your MCP client at it, and let agents work.' },
      ],
    },
    privacy: {
      title: 'Private by design',
      body: 'AIShot runs entirely on your Mac. There is no telemetry and no network egress except an optional update check.',
      points: [
        'On-device capture, OCR, and editing — images never leave your machine.',
        'The MCP server speaks stdio and opens no network socket at all.',
        'Click and type tools are off by default and confirmation-gated.',
        'Developer ID signed and notarized.',
      ],
    },
    download: {
      title: 'Get AIShot',
      requirements: 'Requirements',
      reqItems: ['macOS 15 Sequoia or later', 'Apple silicon or Intel', 'Xcode 26 to build from source'],
      buildTitle: 'Build from source',
    },
    footer: { tagline: 'Native macOS screenshots for humans and AI agents.', note: 'On-device. Open architecture. Built with Swift.' },
  },

  fr: {
    title: 'AIShot — Captures d’écran natives macOS pour les humains et les agents IA',
    description: 'Un outil de capture macOS moderne : captures de région/fenêtre/écran, annotation, OCR, enregistrement — et un serveur MCP local pour que les agents IA capturent et agissent sur votre écran, entièrement en local.',
    nav: { features: 'Fonctions', agents: 'Pour les agents', how: 'Fonctionnement', privacy: 'Confidentialité', download: 'Télécharger', github: 'GitHub' },
    hero: {
      badge: 'Natif · macOS 15+ · Priorité au local',
      title: 'Des captures pensées pour les humains et les agents IA',
      subtitle: 'Capturez, annotez et reconnaissez — puis laissez les agents IA locaux piloter les mêmes capacités via un serveur MCP intégré. Rien ne quitte votre Mac.',
      ctaDownload: 'Commencer',
      ctaGithub: 'Voir le code',
    },
    featuresTitle: 'Tout ce que vous attendez, et plus encore',
    features: [
      { title: 'Capture région, fenêtre et écran', desc: 'Captures ScreenCaptureKit nettes (Retina) avec sélection rapide et minuteur.' },
      { title: 'Annoter', desc: 'Flèches, formes, texte, surligneur, étapes numérotées et floutage de zones sensibles.' },
      { title: 'OCR de texte', desc: 'Reconnaissez le texte d’une zone et copiez-le directement dans le presse-papiers.' },
      { title: 'Pipette & épingle', desc: 'Pipette précise au pixel avec code hex, et épinglez une capture au-dessus de tout.' },
      { title: 'Embellir', desc: 'Encadrez une capture sur un dégradé avec marge, coins arrondis et ombre.' },
      { title: 'Masquage auto', desc: 'Détectez et floutez automatiquement e-mails, numéros de carte et IP.' },
      { title: 'Enregistrement d’écran', desc: 'Enregistrez un écran en vidéo H.264, directement dans votre dossier.' },
      { title: 'Capture défilante', desc: 'Faites défiler et assemblez de longues pages en une seule capture.' },
      { title: 'Recherche dans vos captures', desc: 'Chaque capture est lue par OCR en local : retrouvez-la grâce aux mots qu’elle contient, pas seulement son nom de fichier.' },
      { title: 'Notes, étiquettes & tableau de bord', desc: 'Associez une note et une étiquette de projet à chaque capture, puis parcourez et gérez le tout dans une seule fenêtre.' },
    ],
    agents: {
      title: 'Conçu pour les agents IA',
      body: 'AIShot intègre un serveur Model Context Protocol (MCP) pour que les agents locaux comme Claude Code voient et agissent sur votre écran — en local, sans passer par le cloud. Les outils de capture et de lecture sont toujours disponibles ; ceux qui déplacent la souris ou saisissent du texte demandent une confirmation.',
      toolsTitle: 'Outils MCP',
      tools: [
        { name: 'capture_region / capture_window / capture_display', desc: 'Capture et renvoie l’image avec ses métadonnées.' },
        { name: 'list_displays / list_windows / list_apps', desc: 'Énumère ce qui est à l’écran.' },
        { name: 'ocr', desc: 'Reconnaît le texte d’un écran ou d’une zone.' },
        { name: 'search_captures', desc: 'Retrouve d’anciennes captures d’après le texte qu’elles contiennent, leur note, leur étiquette ou leur nom.' },
        { name: 'get_history', desc: 'Liste les captures récentes.' },
        { name: 'annotate / beautify / redact', desc: 'Transforme les images par programmation.' },
        { name: 'locate', desc: 'Trouve un élément à l’écran par texte et renvoie ses rectangles.' },
        { name: 'switch_app / click / type_text', desc: 'Pilote d’autres apps — soumis à confirmation.' },
      ],
      gated: 'Le serveur communique avec votre agent via stdio et n’ouvre aucun socket réseau. Les outils de saisie restent refusés tant que vous ne les autorisez pas explicitement.',
    },
    how: {
      title: 'Fonctionnement',
      steps: [
        { title: 'Accorder les autorisations', desc: 'Enregistrement de l’écran pour capturer, Accessibilité pour la saisie par les agents.' },
        { title: 'Capturer', desc: 'Utilisez un raccourci global ou la barre des menus pour capturer région, fenêtre ou écran.' },
        { title: 'Modifier & partager', desc: 'Annotez, embellissez, copiez ou enregistrez avec un nom personnalisé.' },
        { title: 'Connecter les agents', desc: 'Activez le serveur dans les réglages, pointez-y votre client MCP et laissez les agents travailler.' },
      ],
    },
    privacy: {
      title: 'Confidentiel par conception',
      body: 'AIShot fonctionne entièrement sur votre Mac. Aucune télémétrie ni transfert réseau, hormis une vérification de mise à jour optionnelle.',
      points: [
        'Capture, OCR et édition en local — les images ne quittent jamais votre machine.',
        'Le serveur MCP communique via stdio et n’ouvre aucun socket réseau.',
        'Les outils de clic et de saisie sont désactivés par défaut et soumis à confirmation.',
        'Signé Developer ID et notarisé.',
      ],
    },
    download: {
      title: 'Obtenir AIShot',
      requirements: 'Prérequis',
      reqItems: ['macOS 15 Sequoia ou ultérieur', 'Apple silicon ou Intel', 'Xcode 26 pour compiler les sources'],
      buildTitle: 'Compiler depuis les sources',
    },
    footer: { tagline: 'Captures d’écran natives macOS pour les humains et les agents IA.', note: 'En local. Architecture ouverte. Conçu avec Swift.' },
  },

  es: {
    title: 'AIShot — Capturas de pantalla nativas de macOS para personas y agentes de IA',
    description: 'Una herramienta de captura moderna para macOS: capturas de región/ventana/pantalla, anotación, OCR, grabación — y un servidor MCP local para que los agentes de IA capturen y actúen en tu pantalla, todo en el dispositivo.',
    nav: { features: 'Funciones', agents: 'Para agentes', how: 'Cómo funciona', privacy: 'Privacidad', download: 'Descargar', github: 'GitHub' },
    hero: {
      badge: 'Nativo · macOS 15+ · Local primero',
      title: 'Capturas pensadas para personas y agentes de IA',
      subtitle: 'Captura, anota y reconoce — y deja que los agentes de IA locales usen las mismas capacidades mediante un servidor MCP integrado. Nada sale de tu Mac.',
      ctaDownload: 'Empezar',
      ctaGithub: 'Ver el código',
    },
    featuresTitle: 'Todo lo que esperas, y más',
    features: [
      { title: 'Captura de región, ventana y pantalla', desc: 'Capturas nítidas (Retina) con ScreenCaptureKit, selección rápida y temporizador.' },
      { title: 'Anotar', desc: 'Flechas, formas, texto, resaltador, pasos numerados y difuminado de datos sensibles.' },
      { title: 'OCR de texto', desc: 'Reconoce el texto de una zona y cópialo directo al portapapeles.' },
      { title: 'Cuentagotas y fijar', desc: 'Cuentagotas preciso con hex y fija una captura sobre todas las ventanas.' },
      { title: 'Embellecer', desc: 'Enmarca una captura sobre un degradado con márgenes, esquinas y sombra.' },
      { title: 'Redacción automática', desc: 'Detecta y difumina correos, tarjetas e IPs automáticamente.' },
      { title: 'Grabación de pantalla', desc: 'Graba una pantalla en vídeo H.264, directo a tu carpeta.' },
      { title: 'Captura con desplazamiento', desc: 'Desplaza y une páginas largas en una sola captura.' },
      { title: 'Busca dentro de tus capturas', desc: 'Cada captura se lee con OCR en el dispositivo: encuéntrala por las palabras que contiene, no solo por su nombre de archivo.' },
      { title: 'Notas, etiquetas y panel', desc: 'Adjunta una nota y una etiqueta de proyecto a cada captura y gestiónalas todas en una sola ventana.' },
    ],
    agents: {
      title: 'Diseñado para agentes de IA',
      body: 'AIShot integra un servidor Model Context Protocol (MCP) para que agentes locales como Claude Code vean y actúen en tu pantalla — en el dispositivo, sin pasar por la nube. Las herramientas de captura y lectura siempre están disponibles; las que mueven el ratón o escriben requieren confirmación.',
      toolsTitle: 'Herramientas MCP',
      tools: [
        { name: 'capture_region / capture_window / capture_display', desc: 'Captura y devuelve la imagen con sus metadatos.' },
        { name: 'list_displays / list_windows / list_apps', desc: 'Enumera lo que hay en pantalla.' },
        { name: 'ocr', desc: 'Reconoce texto en una pantalla o región.' },
        { name: 'search_captures', desc: 'Encuentra capturas anteriores por el texto que contienen, su nota, etiqueta o nombre de archivo.' },
        { name: 'get_history', desc: 'Lista las capturas recientes.' },
        { name: 'annotate / beautify / redact', desc: 'Transforma imágenes mediante programación.' },
        { name: 'locate', desc: 'Encuentra elementos en pantalla por texto y devuelve sus rectángulos.' },
        { name: 'switch_app / click / type_text', desc: 'Controla otras apps — con confirmación.' },
      ],
      gated: 'El servidor se comunica con tu agente por stdio y no abre ningún socket de red. Las herramientas de entrada siguen rechazadas hasta que las autorices explícitamente.',
    },
    how: {
      title: 'Cómo funciona',
      steps: [
        { title: 'Conceder permisos', desc: 'Grabación de pantalla para capturar, Accesibilidad para la entrada de agentes.' },
        { title: 'Capturar', desc: 'Usa un atajo global o la barra de menús para capturar región, ventana o pantalla.' },
        { title: 'Editar y compartir', desc: 'Anota, embellece, copia o guarda con un nombre personalizado.' },
        { title: 'Conectar agentes', desc: 'Apunta tu cliente MCP al servidor integrado y deja que los agentes trabajen.' },
      ],
    },
    privacy: {
      title: 'Privado por diseño',
      body: 'AIShot funciona por completo en tu Mac. Sin telemetría ni tráfico de red, salvo una comprobación de actualizaciones opcional.',
      points: [
        'Captura, OCR y edición en el dispositivo — las imágenes nunca salen de tu equipo.',
        'El servidor MCP se comunica por stdio y no abre ningún socket de red.',
        'Las herramientas de clic y escritura están desactivadas por defecto y piden confirmación.',
        'Firmado con Developer ID y notarizado.',
      ],
    },
    download: {
      title: 'Consigue AIShot',
      requirements: 'Requisitos',
      reqItems: ['macOS 15 Sequoia o posterior', 'Apple silicon o Intel', 'Xcode 26 para compilar el código'],
      buildTitle: 'Compilar desde el código',
    },
    footer: { tagline: 'Capturas de pantalla nativas de macOS para personas y agentes de IA.', note: 'En el dispositivo. Arquitectura abierta. Hecho con Swift.' },
  },
};
