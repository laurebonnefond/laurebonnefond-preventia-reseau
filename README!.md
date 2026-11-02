# PréventIA Réseau

> Laboratoire collaboratif d'innovation IA des Services de Prévention et de Santé au Travail Interentreprises (SPSTI).
> Pilote : **SPSTI 23/87** (Creuse · Haute-Vienne), conçu pour s'ouvrir ensuite à d'autres SPSTI.

**L'IA est un moyen, jamais une fin.** On part d'un besoin du terrain, on teste, on mesure, puis on décide, et la décision reste toujours humaine.

🔗 Site : <https://laurebonnefond.github.io/laurebonnefond-preventia-reseau/>
🧪 Démo sans compte : bouton **« Explorer la démo »** (données fictives, rien n'est enregistré)

---

## Sommaire

1. [Fonctionnalités](#fonctionnalités)
2. [Architecture](#architecture)
3. [Installation](#installation)
4. [Rôles et droits](#rôles-et-droits)
5. [Sécurité et données](#sécurité-et-données)
6. [Images du portail](#images-du-portail)
7. [Structure du dépôt](#structure-du-dépôt)
8. [Feuille de route](#feuille-de-route)

---

## Fonctionnalités

| Rubrique | Ce qu'on y fait |
|---|---|
| 🏠 **Accueil personnel** | Tableau de bord individuel (mes idées, soutiens reçus, tests suivis, temps gagné visé), activité sur 8 semaines, **parcours IA en 5 niveaux**, tuiles d'accès rapide, défi du moment |
| 💡 **Idées** | Déposer une problématique terrain en 2 minutes, sans vocabulaire technique ; soutiens « ça m'intéresse » / « je veux tester » ; commentaires |
| 🧪 **Expérimentations** | Fiche projet en 12 points (hypothèse, protocole, résultats, limites, décision), journal des testeurs, indicateurs estimés **et** mesurés |
| 🧰 **Boîte à outils** | Bibliothèque de prompts copiables, catalogue d'outils IA avec niveau de maturité |
| 💬 **Échanges & équipes** | Fil général du SPSTI, fils privés par équipe, **messages privés 1:1**, temps réel |
| 📁 **Base documentaire** | Dépôt de procédures, modèles vierges et supports, protégés par SPSTI ; partage réseau validé |
| 👥 **Communauté** | Appels à volontaires, défis collectifs, annuaire du SPSTI, SPSTI du réseau |
| 📊 **Tableau de bord du SPSTI** | Indicateurs collectifs (jamais de classement individuel), entonnoir des idées, temps gagné |
| 🛡️ **Administration** | Code d'adhésion, rôles, validation des partages réseau, journal des actions sensibles |
| 🤖 **Assistant IA** | *En construction* : cadrage en cours (voir [feuille de route](#feuille-de-route)) |

### Le cycle d'une idée

```
 Problème ──► Idée ──► Test ──► Bilan ──► Partagé
 (terrain)   (2 min)  (volontaires) (mesure + décision) (réseau des SPSTI)
```

Une idée populaire n'est **jamais** validée par sa seule popularité : pour passer aux statuts « Validée » ou « Partagée », il faut que les résultats **et** la décision aient été documentés. La base de données bloque ce passage tant que ce n'est pas fait.

### Le parcours IA (progression personnelle)

```
🌱 Curieux·se → 💡 Contributeur·rice → 🧪 Testeur·se → 📊 Référent·e → 🌐 Passeur·se
```

C'est un simple indicateur de progression, qui n'est pas cliquable et ne produit aucun classement entre collègues.

---

## Architecture

```
┌──────────────── GitHub Pages ────────────────┐
│  index.html  (application monofichier)       │
│  HTML + CSS + JavaScript, sans build         │
│  assets/  (photos)                           │
└──────────────────────┬───────────────────────┘
                       │ supabase-js v2 (clé publique)
                       ▼
┌──────── Supabase — région eu-west-1 (Irlande, UE) ────────┐
│  Auth        comptes, confirmation e-mail, mot de passe   │
│  Postgres    données + Row Level Security (RLS)           │
│  Realtime    messages d'équipe et messages privés         │
│  Storage     compartiment privé « documents »             │
└───────────────────────────────────────────────────────────┘
```

- **Monofichier** : toute l'application tient dans `index.html` (routeur par `#/…`, rendu par modèles littéraux).
- **Clé publique uniquement** côté navigateur : la sécurité repose entièrement sur les politiques **RLS** en base.
- **Mode démo** : une couche `api` simule Supabase en mémoire avec des données fictives.

---

## Installation

### 1. Base Supabase

Le schéma de base (organisations, adhésions, idées, expérimentations, prompts, outils, défis, journal d'audit et les fonctions `is_member`, `has_role`, `content_guard`…) est déjà en place sur le projet.

Exécuter ensuite **dans cet ordre**, depuis *Supabase → SQL Editor* :

| Ordre | Script | Ajoute |
|---|---|---|
| 1 | `migration_equipes_echanges.sql` | Tables `teams`, `team_members`, `messages` + RLS + temps réel |
| 2 | `migration_messages_documents.sql` | Table `direct_messages`, table `documents`, compartiment Storage `documents` + politiques |

Les scripts sont **ré-exécutables** sans risque : ils utilisent `if not exists` et suppriment chaque politique avant de la recréer.

### 2. Configuration du front

Dans `index.html`, objet `CONFIG` :

```js
const CONFIG = {
  url: 'https://<projet>.supabase.co',
  key: 'sb_publishable_…'   // clé publique : la sécurité repose sur la RLS
};
```

Dans *Supabase → Authentication → URL Configuration*, ajouter l'URL GitHub Pages aux **Redirect URLs** (liens de confirmation et de réinitialisation du mot de passe).

### 3. Déploiement

1. Pousser `index.html` et le dossier `assets/` sur la branche `main`.
2. *Settings → Pages → Deploy from a branch → main / root*.

### 4. Premier SPSTI

1. Créer un compte, puis devenir administrateur réseau (table `network_admins`).
2. *Administration → Ajouter un SPSTI* : le code d'adhésion est généré.
3. Transmettre ce code aux volontaires : ils le saisissent après leur inscription.

---

## Rôles et droits

| Action | Collaborateur | Expérimentateur | Animateur | Admin SPSTI |
|---|:-:|:-:|:-:|:-:|
| Proposer une idée, commenter, soutenir | ✅ | ✅ | ✅ | ✅ |
| Échanges, équipes, messages privés | ✅ | ✅ | ✅ | ✅ |
| Déposer un document, un prompt | ✅ | ✅ | ✅ | ✅ |
| Créer et documenter une expérimentation | | ✅ | ✅ | ✅ |
| Changer un statut, lancer un défi, référencer un outil | | | ✅ | ✅ |
| Gérer les membres et les rôles, valider un partage réseau | | | | ✅ |
| Lire le journal des actions sensibles | | | | ✅ |

Dans une équipe, son **référent** (le créateur, par défaut) peut ajouter des collègues du même SPSTI.

---

## Sécurité et données

### Le feu tricolore des données

| | Niveau | Exemples | Dans le portail |
|---|---|---|---|
| 🟢 | Fictif ou public | Textes INRS, Code du travail, modèles vierges | Autorisé |
| 🟠 | Interne non nominatif | Organisation, statistiques agrégées | Autorisé, jamais vers un outil IA externe non validé |
| 🔴 | Santé ou nominatif | DMST, noms de salariés, documents d'adhérents | **Bloqué** : le formulaire refuse l'envoi |

### Cloisonnement

| Donnée | Qui peut la lire |
|---|---|
| Idées, prompts, documents « Mon SPSTI » | Membres du SPSTI |
| Contenus « Réseau » | Autres SPSTI, **après validation** de l'admin du SPSTI d'origine |
| Contenus « Privé » | Leur auteur uniquement |
| Fil général | Membres du SPSTI |
| Fil d'équipe | Membres de l'équipe uniquement |
| Message privé | **Expéditeur et destinataire uniquement**, y compris vis-à-vis de l'admin |
| Fichier déposé | Uniquement si sa fiche est visible ; lien de téléchargement valable 2 minutes |

### Garde-fous côté base

- Le **trigger `content_guard`** impose l'auteur, réserve les changements de statut aux animateurs et le partage réseau à l'admin, et repasse un contenu en attente s'il est modifié après validation.
- Le **trigger `audit_content`** journalise chaque changement de statut et de partage.
- Le stockage de fichiers est limité à **50 Mo par fichier** et à une liste blanche de formats. Le chemin `<id du SPSTI>/…` est contrôlé par la base.

### Hébergement et RGPD

- Toutes les données sont hébergées dans l'**UE (Irlande)** par Supabase.
- Aucune donnée de santé ne doit être saisie : le portail **n'est pas** un outil de suivi individuel des salariés.
- La charte d'usage figure dans *Mon profil*. Le registre des traitements et la durée de conservation sont à valider avec le DPO du SPSTI.

---

## Images du portail

Les photos sont dans `assets/`. Si l'une d'elles manque, un dégradé de couleur s'affiche à la place.

| Fichier | Utilisé pour |
|---|---|
| `hero.png` | Page d'accueil publique |
| `bandeau-accueil.jpg` | Accueil connecté |
| `bandeau-idees.jpg`, `bandeau-experiences.jpg`, `bandeau-outils.jpg` | Rubriques Innover |
| `bandeau-echanges.jpg`, `bandeau-communaute.jpg` | Rubriques Collaborer |
| `bandeau-tableau.jpg`, `bandeau-admin.jpg` | Pilotage et base documentaire |
| `cover-medical.jpg`, `cover-soin.jpg`, `cover-terrain.jpg`, `cover-ergonomie.jpg`, `cover-administratif.jpg`, `cover-numerique.jpg` | Couvertures des cartes, selon le métier |

Formats conseillés : bandeaux en 1600 × 690 px et couvertures en 800 × 450 px, en JPG de moins de 250 Ko. La partie gauche des bandeaux doit rester sombre, car le texte s'y superpose.
Les images actuelles ont été **générées par IA** : on n'y voit aucune personne réelle, et toutes les scènes sont prises de dos ou sans visage identifiable.

---

## Structure du dépôt

```
.
├── index.html                          Application complète
├── assets/                             Photos (bandeaux + couvertures)
├── migration_equipes_echanges.sql      Équipes et messages d'équipe
├── migration_messages_documents.sql    Messages privés et base documentaire
└── README.md
```

---

## Feuille de route

- [x] Idées, expérimentations, boîte à outils, tableau de bord du SPSTI
- [x] Interface V2 : barre latérale, bandeaux photo, tableau de bord personnel, parcours IA
- [x] Échanges : fil général, équipes, messages privés en temps réel
- [x] Base documentaire protégée par SPSTI
- [ ] **Assistant IA**, à cadrer avant ouverture :
  1. **Fournisseur** : Mistral (français, hébergement UE) ou Claude, avec une clé API cachée dans une Supabase Edge Function ;
  2. **Périmètre** : des réponses fondées sur la base documentaire, sources citées ;
  3. **Garde-fous** : filtre des données sensibles avant envoi, mention « vous échangez avec une IA » (AI Act, art. 50), validation DPO.
- [ ] Groupes thématiques inter-SPSTI
- [ ] Passage à l'offre Supabase Pro dès l'ouverture à d'autres SPSTI (l'offre gratuite plafonne à 1 Go de fichiers)

---

## Crédits

Conçu par **Laure Bonnefond**, infirmière en santé au travail et préventrice au SPSTI 23/87.
Retours et idées : directement dans la Boîte à idées du portail. 💡
