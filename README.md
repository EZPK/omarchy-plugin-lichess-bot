# Omarchy Lichess Bot

Un lanceur de partie contre l'IA Lichess (niveaux 1-8) depuis la barre
Omarchy : choisis le niveau, la couleur et la cadence dans le popup, puis
clique "Nouvelle partie" — une petite fenêtre dédiée crée la partie et
t'emmène directement dessus sur lichess.org.

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

## Prérequis

- Un compte Lichess.
- Un **token d'accès personnel** avec le scope `challenge:write`. Le
  bouton "Créer un token" dans les réglages ouvre la page Lichess avec ce
  scope déjà coché.
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

- Uniquement contre le bot Lichess ; pas de mode joueur contre joueur.
- La partie se joue sur lichess.org, dans la fenêtre ouverte par le
  plugin — pas d'échiquier intégré à la barre.

## License

MIT — see [LICENSE](LICENSE).
