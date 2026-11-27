// mDOWN — textes de l'interface (français d'abord, anglais, espagnol, italien ; mêmes clés dans chaque langue).
import Foundation

enum L {
    /// Première langue préférée du système parmi les quatre prises en charge, sinon l'anglais.
    static let lang: String = {
        for id in Locale.preferredLanguages {
            let code = String(id.prefix(2)).lowercased()
            if ["fr", "en", "es", "it"].contains(code) { return code }
        }
        return "en"
    }()
    static var locale: Locale { Locale(identifier: lang) }
    private static let index = ["fr": 0, "en": 1, "es": 2, "it": 3][lang] ?? 1

    static func t(_ key: String, _ args: CVarArg...) -> String {
        guard let row = raw[key] else { return key }
        let s = row[index]
        return args.isEmpty ? s : String(format: s, locale: locale, arguments: args)
    }

    /// « il y a 3 h » dans la langue de l'appli.
    static func ago(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = locale; f.unitsStyle = .short; f.dateTimeStyle = .numeric
        return f.localizedString(for: d, relativeTo: Date())
    }

    // Ordre des colonnes : fr, en, es, it.
    private static let raw: [String: [String]] = [
        "svc.active": ["Service actif · %@ de mémoire", "Service running · %@ of memory", "Servicio activo · %@ de memoria", "Servizio attivo · %@ di memoria"],
        "paste.ph": ["Collez un lien ou glissez-le ici", "Paste a link or drop it here", "Pegue un enlace o arrástrelo aquí", "Incolla un link o trascinalo qui"],
        "btn.download": ["Télécharger", "Download", "Descargar", "Scarica"],
        "mode.video": ["Vidéo", "Video", "Vídeo", "Video"],
        "mode.audio": ["Audio", "Audio", "Audio", "Audio"],
        "opt.quality": ["Qualité : %@", "Quality: %@", "Calidad: %@", "Qualità: %@"],
        "opt.format": ["Format : %@", "Format: %@", "Formato: %@", "Formato: %@"],
        "q.best": ["Meilleure", "Best", "Mejor", "Migliore"],
        "count.summary": ["%d éléments · %d en cours · %d en attente", "%d items · %d active · %d waiting", "%d elementos · %d en curso · %d en espera", "%d elementi · %d in corso · %d in attesa"],
        "empty.drop": ["Glissez un lien ici", "Drop a link here", "Arrastre un enlace aquí", "Trascina un link qui"],
        "empty.hint": ["mDOWN choisit seul le bon extracteur pour chaque site.", "mDOWN picks the right extractor for each site by itself.", "mDOWN elige solo el extractor adecuado para cada sitio.", "mDOWN sceglie da solo l'estrattore giusto per ogni sito."],
        "pl.items": ["Playlist · %d éléments", "Playlist · %d items", "Lista · %d elementos", "Playlist · %d elementi"],
        "state.analyzing": ["Analyse…", "Analyzing…", "Analizando…", "Analisi…"],
        "state.queued": ["En attente", "Waiting", "En espera", "In attesa"],
        "state.downloading": ["Téléchargement", "Downloading", "Descargando", "Download"],
        "state.done": ["Terminé", "Done", "Terminado", "Completato"],
        "state.failed": ["Échec", "Failed", "Error", "Errore"],
        "state.paused": ["En pause", "Paused", "En pausa", "In pausa"],
        "state.retry": ["Nouvel essai à %@", "Retrying at %@", "Reintento a las %@", "Nuovo tentativo alle %@"],
        "sp.queue": ["file d'attente", "queued", "en cola", "in coda"],
        "sp.prog": ["%d %% · reste %@", "%d %% · %@ left", "%d %% · quedan %@", "%d %% · mancano %@"],
        "sp.pct": ["%d %%", "%d %%", "%d %%", "%d %%"],
        "act.pause": ["Mettre en pause", "Pause", "Pausar", "Metti in pausa"],
        "act.resume": ["Reprendre", "Resume", "Reanudar", "Riprendi"],
        "act.cancel": ["Annuler", "Cancel", "Cancelar", "Annulla"],
        "act.reveal": ["Afficher dans le Finder", "Show in Finder", "Mostrar en el Finder", "Mostra nel Finder"],
        "act.retry": ["Réessayer", "Retry", "Reintentar", "Riprova"],
        "act.remove": ["Retirer de la liste", "Remove from list", "Quitar de la lista", "Rimuovi dalla lista"],
        "eng.upToDate": ["À jour · %@", "Up to date · %@", "Al día · %@", "Aggiornato · %@"],
        "eng.checked": ["Vérifié %@ · sans recompilation", "Checked %@ · no rebuild", "Comprobado %@ · sin recompilar", "Verificato %@ · senza ricompilare"],
        "eng.never": ["Jamais vérifié · sans recompilation", "Never checked · no rebuild", "Nunca comprobado · sin recompilar", "Mai verificato · senza ricompilare"],
        "eng.checking": ["Vérification…", "Checking…", "Comprobando…", "Verifica…"],
        "eng.updating": ["Mise à jour du moteur…", "Updating the engine…", "Actualizando el motor…", "Aggiornamento del motore…"],
        "eng.installing": ["Installation du moteur…", "Installing the engine…", "Instalando el motor…", "Installazione del motore…"],
        "eng.missing": ["Moteur non installé", "Engine not installed", "Motor no instalado", "Motore non installato"],
        "eng.failed": ["Moteur en erreur", "Engine error", "Error del motor", "Errore del motore"],
        "eng.rolled": ["Version précédente rétablie après un test raté", "Previous version restored after a failed test", "Versión anterior restaurada tras una prueba fallida", "Versione precedente ripristinata dopo un test fallito"],
        "eng.check": ["Vérifier maintenant", "Check now", "Comprobar ahora", "Verifica ora"],
        "eng.channel": ["Canal", "Channel", "Canal", "Canale"],
        "ch.stable": ["Stable", "Stable", "Estable", "Stabile"],
        "ch.nightly": ["Nightly", "Nightly", "Nightly", "Nightly"],
        "plat.ok": ["Fonctionne", "Working", "Funciona", "Funziona"],
        "plat.fail": ["Ne répond pas", "Not working", "No responde", "Non risponde"],
        "plat.untested": ["Non testé", "Not tested", "Sin probar", "Non testato"],
        "plat.testing": ["Test…", "Testing…", "Probando…", "Test…"],
        "plat.login": ["Compte requis", "Account needed", "Cuenta necesaria", "Account richiesto"],
        "set.wclaude": ["Tester les plateformes avec compte via la session de wCLAUDE (si reliée)", "Test account platforms with wCLAUDE's session (if linked)", "Probar las plataformas con cuenta con la sesión de wCLAUDE (si está enlazada)", "Testa le piattaforme con account con la sessione di wCLAUDE (se collegata)"],
        "plat.tested": ["Testé %@", "Tested %@", "Probado %@", "Testato %@"],
        "plat.jobok": ["Dernier téléchargement réussi %@", "Last download succeeded %@", "Última descarga correcta %@", "Ultimo download riuscito %@"],
        "plat.jobfail": ["Dernier échec %@", "Last failure %@", "Último fallo %@", "Ultimo errore %@"],
        "today.done": ["Terminés", "Done", "Terminados", "Completati"],
        "today.received": ["Reçus", "Received", "Recibidos", "Ricevuti"],
        "today.errors": ["Erreurs", "Errors", "Errores", "Errori"],
        "dest.change": ["Changer", "Change", "Cambiar", "Cambia"],
        "dest.clip": ["Lien copié", "Copied link", "Enlace copiado", "Link copiato"],
        "dest.clipOn": ["Détecté auto", "Auto-detected", "Detección auto", "Rilevato auto"],
        "dest.clipOff": ["Désactivé", "Off", "Desactivado", "Disattivato"],
        "foot.engine": ["Moteur vérifié par somme SHA-256 · jamais de recompilation", "Engine verified by SHA-256 · never rebuilt", "Motor verificado por SHA-256 · sin recompilar", "Motore verificato con SHA-256 · mai ricompilato"],
        "foot.menu": ["Démarre avec la session · icône dans la barre des menus", "Starts with your session · menu bar icon", "Se inicia con la sesión · icono en la barra de menús", "Si avvia con la sessione · icona nella barra dei menu"],
        "menu.paste": ["Télécharger le lien copié", "Download copied link", "Descargar el enlace copiado", "Scarica il link copiato"],
        "menu.open": ["Ouvrir mDOWN", "Open mDOWN", "Abrir mDOWN", "Apri mDOWN"],
        "menu.idle": ["Aucun téléchargement en cours", "No active downloads", "Ninguna descarga en curso", "Nessun download in corso"],
        "menu.engine": ["Vérifier le moteur", "Check the engine", "Comprobar el motor", "Verifica il motore"],
        "menu.settings": ["Réglages…", "Settings…", "Ajustes…", "Impostazioni…"],
        "menu.about": ["À propos de mDOWN", "About mDOWN", "Acerca de mDOWN", "Informazioni su mDOWN"],
        "menu.quit": ["Quitter mDOWN", "Quit mDOWN", "Salir de mDOWN", "Esci da mDOWN"],
        "set.title": ["Réglages", "Settings", "Ajustes", "Impostazioni"],
        "set.folder": ["Dossier d'enregistrement", "Download folder", "Carpeta de descarga", "Cartella di download"],
        "set.concurrent": ["Téléchargements simultanés", "Simultaneous downloads", "Descargas simultáneas", "Download simultanei"],
        "set.cookies": ["Cookies du navigateur", "Browser cookies", "Cookies del navegador", "Cookie del browser"],
        "set.cookies.none": ["Aucun", "None", "Ninguno", "Nessuno"],
        "set.cookies.help": ["Pour les vidéos réservées à un compte (âge, abonnés). Safari demande l'accès complet au disque.", "For videos that need an account (age, subscribers). Safari needs Full Disk Access.", "Para vídeos que requieren una cuenta (edad, suscriptores). Safari necesita acceso total al disco.", "Per i video riservati a un account (età, iscritti). Safari richiede l'accesso completo al disco."],
        "set.autoengine": ["Mettre à jour le moteur automatiquement", "Update the engine automatically", "Actualizar el motor automáticamente", "Aggiorna il motore automaticamente"],
        "set.autoapp": ["Installer automatiquement les mises à jour de l'appli", "Install app updates automatically", "Instalar automáticamente las actualizaciones de la app", "Installa automaticamente gli aggiornamenti dell'app"],
        "set.appupdate": ["Rechercher une mise à jour de l'appli", "Check for an app update", "Buscar una actualización de la app", "Cerca un aggiornamento dell'app"],
        "set.login": ["Ouvrir à l'ouverture de session", "Open at login", "Abrir al iniciar sesión", "Apri all'accesso"],
        "set.clip": ["Détecter le lien copié", "Detect the copied link", "Detectar el enlace copiado", "Rileva il link copiato"],
        "set.ext.title": ["Extension du navigateur", "Browser extension", "Extensión del navegador", "Estensione del browser"],
        "set.ext.install": ["Installer", "Install", "Instalar", "Installa"],
        "set.ext.reinstall": ["Réinstaller", "Reinstall", "Reinstalar", "Reinstalla"],
        "set.ext.next": ["Relancez %@, puis confirmez l'ajout de l'extension mDOWN dans son menu (⋮ ou ≡).", "Relaunch %@, then confirm adding the mDOWN extension in its menu (⋮ or ≡).", "Reinicie %@ y confirme la adición de la extensión mDOWN en su menú (⋮ o ≡).", "Riavvia %@, poi conferma l'aggiunta dell'estensione mDOWN nel suo menu (⋮ o ≡)."],
        "set.ext.fail": ["Installation impossible (paquet absent de cette version).", "Installation failed (package missing from this build).", "No se pudo instalar (paquete ausente de esta versión).", "Installazione impossibile (pacchetto assente in questa versione)."],
        "set.ext.none": ["Aucun navigateur compatible détecté (Brave, Chrome, Edge, Chromium, Vivaldi).", "No compatible browser detected (Brave, Chrome, Edge, Chromium, Vivaldi).", "No se detectó ningún navegador compatible (Brave, Chrome, Edge, Chromium, Vivaldi).", "Nessun browser compatibile rilevato (Brave, Chrome, Edge, Chromium, Vivaldi)."],
        "set.ext.bookmarklet": ["Signet pour Safari et les autres navigateurs", "Bookmarklet for Safari and other browsers", "Marcador para Safari y otros navegadores", "Segnalibro per Safari e altri browser"],
        "set.copy": ["Copier", "Copy", "Copiar", "Copia"],
        "set.copied": ["Copié", "Copied", "Copiado", "Copiato"],
        "set.show": ["Afficher", "Show", "Mostrar", "Mostra"],
        "set.access": ["Dossiers où un agent peut enregistrer. Tout autre dossier attend votre accord.", "Folders where an agent may save files. Any other folder waits for your approval.", "Carpetas donde un agente puede guardar. Cualquier otra espera su aprobación.", "Cartelle dove un agente può salvare. Ogni altra attende la tua approvazione."],
        "set.access.add": ["Ajouter un dossier…", "Add a folder…", "Añadir una carpeta…", "Aggiungi una cartella…"],
        "access.ask": ["Un agent demande : %@", "An agent asks for: %@", "Un agente solicita: %@", "Un agente chiede: %@"],
        "access.allow": ["Autoriser", "Allow", "Permitir", "Consenti"],
        "access.deny": ["Refuser", "Deny", "Rechazar", "Rifiuta"],
        "menu.allow": ["Autoriser l'agent à écrire dans « %@ »", "Allow the agent to write in “%@”", "Permitir al agente escribir en «%@»", "Consenti all'agente di scrivere in «%@»"],
        "menu.deny": ["Refuser « %@ »", "Deny “%@”", "Rechazar «%@»", "Rifiuta «%@»"],
        "set.done": ["Fermer", "Close", "Cerrar", "Chiudi"],
        "upd.checking": ["Recherche…", "Checking…", "Buscando…", "Ricerca…"],
        "upd.uptodate": ["L'appli est à jour (%@)", "The app is up to date (%@)", "La app está al día (%@)", "L'app è aggiornata (%@)"],
        "upd.available": ["Version %@ disponible", "Version %@ available", "Versión %@ disponible", "Versione %@ disponibile"],
        "upd.downloading": ["Installation…", "Installing…", "Instalando…", "Installazione…"],
        "upd.install": ["Installer", "Install", "Instalar", "Installa"],
        "upd.err.none": ["Aucune version trouvée.", "No release found.", "No se encontró ninguna versión.", "Nessuna versione trovata."],
        "upd.err.download": ["Téléchargement impossible.", "Download failed.", "Descarga imposible.", "Download impossibile."],
        "upd.err.signature": ["Signature invalide : mise à jour refusée.", "Invalid signature: update refused.", "Firma no válida: actualización rechazada.", "Firma non valida: aggiornamento rifiutato."],
        "upd.err.version": ["Version inattendue.", "Unexpected version.", "Versión inesperada.", "Versione inattesa."],
        "err.noengine": ["Le moteur n'a pas pu être installé. Vérifiez votre connexion.", "The engine could not be installed. Check your connection.", "No se pudo instalar el motor. Compruebe su conexión.", "Impossibile installare il motore. Controlla la connessione."],
        "err.repair": ["Le moteur reçoit un correctif · nouvel essai automatique", "The engine is getting a fix · automatic retry", "El motor recibe una corrección · reintento automático", "Il motore riceve una correzione · nuovo tentativo automatico"],
        "err.badurl": ["Lien non reconnu.", "Link not recognized.", "Enlace no reconocido.", "Link non riconosciuto."],
        "about.version": ["Version %@ (%@)", "Version %@ (%@)", "Versión %@ (%@)", "Versione %@ (%@)"],
        "about.collection": ["DESKTOP MAC TOOLKIT", "DESKTOP MAC TOOLKIT", "DESKTOP MAC TOOLKIT", "DESKTOP MAC TOOLKIT"],
        "about.tagline": ["Téléchargeur de vidéos et de sons, léger, au moteur d'analyse qui se met à jour seul.", "A light video and audio downloader whose extraction engine updates itself.", "Descargador ligero de vídeo y audio cuyo motor de análisis se actualiza solo.", "Downloader leggero di video e audio con un motore di analisi che si aggiorna da solo."],
        "about.authors": ["Stéphan Le Gac Savoye", "Stéphan Le Gac Savoye", "Stéphan Le Gac Savoye", "Stéphan Le Gac Savoye"],
        "about.license": ["Usage personnel. Moteur d'extraction : yt-dlp (Unlicense).", "Personal use. Extraction engine: yt-dlp (Unlicense).", "Uso personal. Motor de extracción: yt-dlp (Unlicense).", "Uso personale. Motore di estrazione: yt-dlp (Unlicense)."],
        "about.disclaimer": ["Ne téléchargez que des contenus dont vous avez le droit de conserver une copie.", "Only download content you are allowed to keep a copy of.", "Descargue solo contenido del que tenga derecho a conservar una copia.", "Scarica solo contenuti di cui hai il diritto di conservare una copia."],
        "about.support": ["♥ Soutenir le projet", "♥ Support the project", "♥ Apoyar el proyecto", "♥ Sostieni il progetto"],
    ]
}
