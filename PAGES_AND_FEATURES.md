# Mkzik — Pages, fonctionnalités et modales

Référence complète de l'app mobile Mkzik, à répliquer sur le site web.
À utiliser avec `DESIGN_SYSTEM.md` (couleurs/typo) pour reproduire le même produit.

## Navigation générale

Barre de navigation basse à 4 onglets : **Accueil**, **Recherche**, **Bibliothèque**, **Profil**.
Un mini-lecteur persistant apparaît en bas dès qu'un titre est en lecture, au-dessus d'éventuelles bannières de notification (import en cours, etc.).

---

## 1. Authentification

### Splash (Auth Gate)
Écran de chargement au démarrage pendant la vérification de session (logo + spinner). Redirige automatiquement vers Login ou l'app.

### Login
- Logo, titre "Connexion", sous-titre "Heureux de te revoir 👋"
- Champ email, champ mot de passe (avec bascule visibilité)
- Bandeau d'erreur si échec
- Bouton "Se connecter" (accent, spinner pendant le chargement)
- Séparateur "ou"
- Bouton "Continuer avec Google"
- Lien "Pas de compte ? Inscris-toi" → Register

### Register
- Bouton retour
- Champs : pseudo*, email*, mot de passe* (+ confirmation*), nom/prénom (optionnels, côte à côte), date de naissance (date picker), description (multiligne, optionnel)
- Case à cocher consentement RGPD + texte légal
- Bouton "S'inscrire" (spinner pendant chargement)
- Bandeau d'erreur si échec

---

## 2. Accueil

- Header : logo, cloche de notifications, avatar profil
- **Bandeau vedette** (si dispo) : badge "TITRE EN VEDETTE", titre en dégradé, artiste + durée, bouton "Écouter", pochette flottante en rotation
- Section **"Dernière sortie"** — scroll horizontal, lien "Voir tout"
- Section **"Suggestions YouTube"** — scroll horizontal (si dispo)
- Section **"Suggestions SoundCloud"** — scroll horizontal (si dispo)
- Section **"Historique"** — scroll horizontal, lien "Voir tout"
- Section **"Artistes recommandés"** — avatars circulaires, scroll horizontal
- Pull-to-refresh

Clics : carte titre → lecture ; "Voir tout" → liste complète ; avatar artiste → profil.

---

## 3. Recherche

- Barre de recherche (debounce ~350ms), autofocus, bouton clear
- **État vide** : grille de genres à cliquer (exploration rapide)
- **État suggestions** (avant validation) : section "Suggestions" (combinée Zik + Users + Externe) + section "Récents" (avec "Tout effacer")
- **État résultats** :
  - Onglets : **ZIK** / **USER** / **EXTERNE**
  - Chips de tri (Zik/Externe) : Pertinence, Date, Écoutes
  - Filtres plateforme (Externe uniquement) : Tout, YT Music, SoundCloud
  - Liste de résultats (titre ou utilisateur)
  - Loader de pied de liste tant que les sources externes streament (SSE)

Clics : titre → lecture ; "…" → menu d'actions ; utilisateur → profil.

---

## 4. Bibliothèque

- Header "Ma librairie" + bouton "Créer" (playlist)
- Onglets : **Tout** (mix playlists + favoris, trié par récence) / **Favoris** / **Playlists**
- Playlists affichées avec pochette dégradée, titre, nombre de titres, menu "…" (Renommer / Supprimer)
- Pull-to-refresh

### Modale — Créer/renommer playlist
Dialogue simple : champ texte (autofocus), boutons Annuler / OK.

### Modale — Supprimer playlist
Dialogue de confirmation : "Supprimer ? La playlist « {titre} » sera supprimée." Boutons Annuler / Supprimer (rouge).

### Détail d'une playlist
- Header : retour, titre, nombre de titres, bouton "Tout lire" (circulaire dégradé)
- Liste de titres avec **swipe pour retirer** (fond rouge + icône suppression)
- État vide : icône + "Playlist vide, ajoute des titres depuis le menu…"

---

## 5. Lecteur / Titre

### Player (plein écran, ouvert depuis le mini-lecteur)
- Fond : pochette floutée ou dégradé + effet géométrique animé, voile sombre pour lisibilité, lueur violette diffuse
- Barre du haut : poignée de glisser, bouton file d'attente, bouton fermer
- **Vue normale** : grande pochette (effet verre), titre en dégradé, artiste (cliquable → profil), ligne de paroles synchronisée en cours
- **Vue paroles** (bascule) : titre compact + paroles défilantes + bouton plein écran
- Panneau de contrôle (effet verre/blur) :
  - Ligne d'actions : Like, Paroles (bascule), Partager, Plus (menu)
  - Forme d'onde interactive (cliquable pour avancer/reculer)
  - Temps écoulé / total
  - Contrôles : aléatoire, précédent, lecture/pause (bouton dégradé), suivant, répétition (aucune/toutes/une seule)
- Fermeture : glisser vers le bas (>25% écran ou vitesse suffisante)

### Paroles plein écran
Fond flouté + voile, titre/artiste en en-tête, paroles centrées, cliquables pour naviguer dans le morceau, bouton fermer.

### Page titre (détail)
- Fond dégradé + lueur, bouton fermer
- Grande pochette, titre en dégradé, artiste cliquable, badges plateforme (YouTube/SoundCloud)
- Pastilles stats : durée, écoutes, likes
- Bouton "Écouter" (dégradé)
- Icônes d'action : Like, Ajouter à la file, Partager, Importer (si titre externe non importé)

### Liste générique ("Voir tout")
Liste paginée à défilement infini (chargement à ~400px du bas), utilisée pour "Dernière sortie", "Historique", etc. Pull-to-refresh.

---

## 6. Profil

- Section héro : couverture (dégradé ou image), avatar circulaire débordant centré
- Bouton retour (si poussé) / bouton déconnexion (si profil perso, onglet)
- Pseudo + @handle
- Bouton "Modifier le profil" (soi-même) ou "Suivre/Suivi" (autre utilisateur)
- Carte stats : abonnés, abonnements, écoutes totales (compteur en dégradé)
- **Carte YouTube Music** (profil perso uniquement) : icône YT, "Importer playlists et likes" → ouvre l'écran YouTube
- Bio (si renseignée)
- Section "Ziks" (titres de l'utilisateur) + compteur
- Pull-to-refresh

### Modifier le profil
- Sélecteur de couverture + sélecteur d'avatar (superposition icône "+"), doivent être choisis ensemble
- Bouton "Mettre à jour les photos" (actif seulement si les deux sont sélectionnées)
- Section "Informations" : pseudo, email, nom/prénom, date de naissance (date picker), nouveau mot de passe (optionnel)
- Bouton "Enregistrer" (champs texte séparés des photos)

### Connexion YouTube Music
**Non connecté** : icône, message explicatif, bouton rouge "Connecter YouTube Music" (spinner pendant OAuth), note "Tu seras redirigé vers Google…"

**Connecté** :
- Section "Likes YouTube" : bouton "Importer mes likes" (spinner + résultat "X/Y titres importés")
- Section "Mes playlists" : liste de playlists (miniature, titre, nombre de titres, bouton import individuel avec spinner/coche/résultat)

**Token expiré** : message "Ta connexion YouTube a expiré." + bouton "Reconnecter YouTube"

---

## 7. Modales et bottom sheets transverses

### Menu d'actions d'un titre (universel, accessible partout via "…")
Bottom sheet avec poignée de glisser, en-tête (pochette + titre + artiste + badge plateforme), puis liste d'actions :
- Jouer ensuite
- Ajouter à la liste courante
- Liker / Retirer des favoris (masqué si externe non importé)
- Ajouter à une playlist (masqué si externe non importé)
- Partager (masqué si externe non importé)
- Télécharger hors ligne
- Importer sur Mkzik (visible seulement si externe non importé, accent)

### Ajouter à une playlist
Bottom sheet listant les playlists de l'utilisateur (icône + nom), état vide "Aucune playlist — crée-en une dans la Bibliothèque."

### File d'attente (Queue)
Bottom sheet plein écran scrollable :
- En-tête "File d'attente" + compteur + fermer
- Bouton "Mode radio" (lance un flux de titres similaires)
- Section "En lecture" (titre courant surligné)
- Section "À suivre" — liste réordonnable par glisser-déposer, croix pour retirer un titre, clic pour sauter directement dessus

---

## Principes d'interaction transverses

1. **Lecture d'un titre** : cliquable partout, ouvre la lecture avec la file contextuelle (playlist, résultats de recherche, profil, etc.)
2. **Menu contextuel universel** : le bouton "…" ouvre toujours le même sheet d'actions de titre
3. **Confirmations** : dialogues simples pour supprimer/renommer une playlist
4. **Feedback** : toasts pour actions rapides (partager, ajouter à la file), bannières persistantes pour les imports en cours
5. **Pull-to-refresh** disponible sur toutes les listes principales
