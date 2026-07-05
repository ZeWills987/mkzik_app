# Mkzik — Design System

Charte visuelle de l'app mobile Mkzik, à répliquer à l'identique sur le site web.
Thème **sombre**, accent violet, typo Nunito.

## Palette (CSS custom properties)

```css
:root {
  /* Accent */
  --accent:        #7C5CFC;  /* violet principal (boutons, actifs, liens) */
  --accent-light:  #A084FD;  /* violet clair (secondaire, hover) */

  /* Fonds */
  --bg:            #0D0D0D;  /* fond global (scaffold) */
  --surface:       #1A1A2E;  /* barres, nav, surfaces */
  --card:          #16213E;  /* cartes */
  --card-alt:      #1E1E30;  /* cartes alternatives */
  --sheet-bg:      #15151F;  /* bottom sheets / modales */
  --mini-player:   #1C1C2E;  /* barre mini-lecteur */

  /* Texte */
  --text-primary:   #FFFFFF; /* titres, texte principal */
  --text-secondary: #AAAAAA; /* texte secondaire, labels */

  /* Bordures / séparateurs */
  --border:      #2A2A40;    /* bordures champs, barres */
  --border-soft: #26263A;    /* séparateurs discrets */
  --divider:     #1E1E2E;    /* diviseurs */

  /* Sémantiques */
  --error:      #E8375A;     /* erreur (bordure/fond) */
  --error-text: #E8607A;     /* texte erreur */
  --user-blue:  #4A90D9;     /* avatars / badge USER */
  --badge-gray: #8A8AA0;     /* badge EXT */
}
```

## Typographie

Police : **Nunito** (Google Fonts). Fallback : `system-ui, sans-serif`.

```css
@import url('https://fonts.googleapis.com/css2?family=Nunito:wght@400;500;600;700;800&display=swap');
body { font-family: 'Nunito', system-ui, sans-serif; }
```

| Rôle             | Taille | Graisse | Couleur          |
|------------------|--------|---------|------------------|
| Headline large   | 24px   | 800     | --text-primary   |
| Headline medium  | 20px   | 700     | --text-primary   |
| Title large      | 16px   | 600     | --text-primary   |
| Title medium     | 14px   | 500     | --text-primary   |
| Body             | 13px   | 400     | --text-secondary |
| Label small      | 11px   | 400     | --text-secondary |

## Composants

**Boutons primaires** : fond `--accent`, texte blanc, `border-radius: 10px`, pas d'ombre.
**Boutons YouTube** : fond `#FF0000`, texte blanc, `border-radius: 10px`.
**Cartes** : fond `--card`, `border-radius: 12px`, bordure optionnelle `--border-soft`.
**Champs de saisie** : fond `--surface`, bordure `--border`, `border-radius: 10px`, texte `--text-primary`.
**Bordures arrondies** : 10–12px standard.
**Navigation** : fond `--surface`, item actif `--accent`, inactif `--text-secondary`, sans élévation.

## Principes

- Thème **exclusivement sombre** (pas de mode clair).
- Accent violet utilisé avec parcimonie : états actifs, CTA principaux, liens.
- Hiérarchie par la graisse (800 → 400) plutôt que par la taille.
- Contrastes doux entre surfaces (`--bg` → `--surface` → `--card`) pour la profondeur.
- Interlignes aérés, coins arrondis partout.
