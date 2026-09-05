# Claude Code Docker container

Une image Docker contenant [Claude Code](https://claude.com/claude-code), reconstruite
automatiquement à chaque nouvelle version publiée sur npm.

Il n'existe pas d'image officielle : Anthropic publie une *Dev Container Feature*, et
qualifie son propre conteneur de référence de « working example rather than a maintained
base image ». Ce dépôt comble ce manque, sans rien modifier au binaire.

## Utilisation

```bash
docker run --rm -it \
  -v claude_home:/home/node \
  -v "$PWD:/workspace" \
  ghcr.io/dragnix-tigerblue77/claude-code-docker-container:stable
```

**Montez le répertoire personnel entier**, pas seulement `~/.claude`. L'état
d'authentification vit dans deux endroits : `~/.claude/` **et** `~/.claude.json`, qui se
trouve *à côté* du répertoire et non dedans. N'en persister qu'un seul donne une
déconnexion apparemment aléatoire à chaque recréation du conteneur.

## Tags disponibles

| Tag | Contenu |
|---|---|
| `stable` | Suit le dist-tag npm `stable`, qui a quelques versions de retard sur `latest`. **Recommandé.** |
| `<version>` | Une version exacte, par exemple `2.1.236`. Immuable. |

Le canal suivi se change avec la variable de dépôt `NPM_DIST_TAG` (`stable` par défaut),
ou ponctuellement par l'entrée `dist_tag` du déclenchement manuel.

## Comment l'image est construite

Le workflow tourne **chaque lundi**, et peut être déclenché à la main. À chaque exécution
il demande à npm ce que résout le dist-tag suivi, demande au registre si cette version est
déjà publiée, et **s'arrête là si c'est le cas**. Un cron qui construirait à chaque fois
publierait cinquante-deux images identiques par an, et rendrait l'historique des versions
inutilisable pour savoir quand quelque chose a réellement changé.

Avant d'être poussée, l'image est **exécutée** : `claude --version` doit renvoyer la
version avec laquelle elle a été construite. Une image qui se construit n'est pas une
image qui démarre.

## Ce que contient l'image

Une base Node 24 (LTS active), le paquet `@anthropic-ai/claude-code` installé à une
version **épinglée**, et le strict nécessaire autour : `git`, `ripgrep` (sans lui la
recherche de fichiers retombe sur un chemin bien plus lent), `jq`, `less`.

L'auto-updater est désactivé : l'image est reconstruite à chaque version, et un binaire
qui se met à jour tout seul dans un conteneur recréé depuis l'image à chaque redémarrage
est une modification qui disparaît en silence.

Le conteneur tourne en utilisateur non privilégié.

## Authentification

Aucun identifiant n'est inclus dans l'image. Chaque personne s'authentifie avec les
siens, au premier lancement, et ils persistent dans le volume monté sur le répertoire
personnel.

À noter : Anthropic autorise explicitement l'hébergement du **binaire non modifié**, ce
que fait ce dépôt. En revanche, router des requêtes à travers les identifiants d'un
abonnement Free, Pro ou Max **pour le compte d'autrui** n'est pas permis — chacun
s'authentifie avec son propre compte.

## Licence

Voir [LICENSE](LICENSE). Claude Code lui-même reste soumis aux conditions d'Anthropic.
