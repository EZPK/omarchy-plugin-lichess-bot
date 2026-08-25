# Omarchy Lichess Bot

Un lanceur de partie Lichess depuis la barre Omarchy : contre le bot
(niveaux 1-8) ou contre un joueur humain de ton niveau. Choisis
l'adversaire, la couleur et la cadence dans le popup, puis clique
"Nouvelle partie" — une petite fenêtre dédiée crée la partie (ou
recherche un adversaire) et t'emmène directement dessus sur lichess.org.

## Pourquoi pas un échiquier intégré au shell ?

La première version de ce plugin rendait l'échiquier directement dans la
barre et jouait les coups via `curl`. Ça ne fonctionnait pas de façon
fiable : `curl`, lancé comme processus enfant de Quickshell, produisait
systématiquement une requête que Lichess traitait comme sans corps —
confirmé octet par octet avec `curl --trace-ascii` (la requête envoyée
était correcte), donc l'écart se situait entre `curl` et le serveur, pas
dans quoi que ce soit que ce plugin contrôlait. La même requête exacte,
lancée à la main dans un terminal, fonctionnait à chaque fois.

Un vrai navigateur a sa propre pile réseau, indépendante de ce problème.
L'API Lichess renvoie `Access-Control-Allow-Origin: *`, donc un `fetch()`
cross-origin depuis la petite page locale (`webapp/launch.html`) vers
`lichess.org` est autorisé — c'est cette page, ouverte dans une fenêtre
"app" du navigateur (sans barre d'adresse ni onglets), qui crée la partie
puis redirige directement dessus.

## Deux modes

- **Bot Lichess** : niveau 1-8, couleur, cadence. Crée la partie
  immédiatement (`POST /api/challenge/ai`).
- **Joueur, même niveau** : renseigne ton classement Elo approximatif ;
  le plugin cherche un adversaire non classé dans ±150 points autour
  (`POST /api/board/seek`). La recherche reste ouverte dans la fenêtre
  jusqu'à trouver quelqu'un (abandon au bout de 5 minutes) — Lichess
  n'indique pas directement la partie créée par cet appel, la page
  surveille donc en parallèle le flux d'évènements du compte
  (`GET /api/stream/event`) pour détecter le début de partie.

## Prérequis

- Un compte Lichess.
- Un **token d'accès personnel** avec les scopes `challenge:write` (mode
  bot) et `board:play` (mode joueur, recherche + flux d'évènements). Le
  bouton "Créer un token" dans les réglages ouvre la page Lichess avec
  les deux scopes déjà cochés.
- Un navigateur basé sur Chromium installé (`brave` par défaut — change
  `launcherProc.command` dans `BarWidget.qml` si tu utilises un autre
  navigateur compatible `--app=`).

## Installation

```sh
omarchy plugin add https://github.com/EZPK/omarchy-plugin-lichess-bot --enable
```

Ou manuellement :

```sh
git clone https://github.com/EZPK/omarchy-plugin-lichess-bot \
  ~/.config/omarchy/plugins/lichess-bot
omarchy plugin enable lichess-bot
```

## Retrait

```sh
omarchy plugin remove lichess-bot
```

Ou supprime directement `~/.config/omarchy/plugins/lichess-bot`.

## Sécurité

- Le token est stocké **en clair** dans
  `~/.local/state/omarchy/lichess-bot-settings.json` (même emplacement
  que l'état propre du shell Omarchy), et seulement après avoir été
  vérifié avec succès contre l'API Lichess. Crée un token dédié à ce
  plugin plutôt que de réutiliser un token existant, pour pouvoir le
  révoquer indépendamment depuis
  [lichess.org/account/oauth/token](https://lichess.org/account/oauth/token).
- Le token voyage dans le fragment (`#...`) de l'URL passée au navigateur
  au lancement — jamais envoyé à un serveur en tant que tel, mais
  **brièvement visible dans la liste des processus locaux** (`ps`) le
  temps du lancement, et dans l'historique du navigateur. Sur une machine
  mono-utilisateur (le cas d'un poste Hyprland/Omarchy personnel),
  l'exposition est nulle ; sur une machine partagée, garde ça en tête.

## Limites

- La recherche d'adversaire humain est toujours en partie non classée
  (`rated: false`) — pas d'impact sur le classement de personne.
- La partie se joue sur lichess.org, dans la fenêtre ouverte par le
  plugin — pas d'échiquier intégré à la barre.

## License

MIT — see [LICENSE](LICENSE).
