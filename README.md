# hexapod_v6

Mod Luanti (Minetest) qui ajoute un hexapod pilotable au clavier de facon
**continue et fluide**, observe depuis une **camera exterieure a la
troisieme personne**.


## Fonctionnement

- Le mod ajoute un objet `hexapod_v6:pod` : un cube de **3x3x3 nodes** (des
  entites, pas des nodes de la carte, pour un deplacement fluide hors grille
  voxel), compose de **27 pieces individuelles** de la taille d'un vrai node
  (voir "Assemblage en 27 nodes" ci-dessous). C'est la **tete** : 5 cubes
  identiques (le **corps**) la suivent a la queue leu leu (voir "Tete et
  corps" ci-dessous), et 6 **pattes** (3 paires) lui sont attachees (voir
  "Pattes" ci-dessous).
- Un clic droit sur un bloc pose l'item `hexapod_v6:pod` qui fait apparaitre
  l'entite pilotable a cet endroit, avec un message de confirmation indiquant
  ses coordonnees.
- Un clic droit sur le cube prend les commandes (message
  "*Vous prenez les commandes du cube. Clic droit pour descendre.*"). Un
  second clic droit du meme joueur les relache (message
  "*Vous descendez du corps.*").

### Pilotage du hexapod

Tant que les touches de deplacement du joueur restent enfoncees, le hexapod
bouge en continu (vitesse proportionnelle au temps ecoule, mise a jour a
chaque pas de simulation) :

- **Haut** : avance dans la direction actuellement regardee par le hexapod.
- **Bas** : recule.
- **Gauche** : pivote vers la gauche (rotation sur place).
- **Droite** : pivote vers la droite (rotation sur place).

**Son de moteur.** Un son en boucle (`hexapod_v6.engine_sound`, repris de
`hexapod_v3`) joue tant que le hexapod avance (**Haut**, `signed_speed`
strictement positif), et s'arrete des qu'il ne va plus vers l'avant
(arret, marche arriere ou pivot sur place) -- meme fonction generique
`set_looping_sound` que `hexapod_v3.update_engine_sound`.

**Son de direction.** Un autre son en boucle (`hexapod_v6.turn_sound`,
repris de `hexapod_v3`) joue tant que le hexapod pivote (**Gauche** ou
**Droite**), que ce soit sur place ou en avancant/reculant en meme temps --
meme fonction `set_looping_sound`, comme `hexapod_v3.update_turn_sound`.

### Camera a la troisieme personne

Des que le joueur prend les commandes :

- Il **n'est plus positionne sur le node** : il est attache a une entite
  invisible ("camera_rig") repositionnee a chaque pas de simulation pour
  rester a distance fixe (`hexapod_v6.camera_distance`, 6 noeuds par
  defaut) derriere son propre regard, de sorte que le hexapod reste
  **exactement au centre de sa vue**, comme une camera satellite qui orbite
  autour de lui.
- Il **garde le controle libre de la souris** : en tournant la tete, il
  change la direction depuis laquelle il observe le hexapod (il peut ainsi
  tourner librement tout autour), le hexapod restant toujours centre.
- Il **perd son propre deplacement** pendant le pilotage (vitesse de marche,
  saut et gravite mis a zero via `set_physics_override`, et position figee
  par l'attache), afin que ses touches de direction ne servent qu'a
  controler le hexapod et non a le faire marcher lui-meme. Sa physique
  d'origine est restauree des qu'il relache les commandes (ou s'il se
  deconnecte pendant le pilotage).
- La camera **suit le hexapod en permanence** lors de ses deplacements et
  rotations, puisqu'elle est recalculee a chaque pas a partir de la
  position courante du node.

**Pourquoi une entite intermediaire plutot que deplacer directement le
joueur ?** Cote moteur, `ObjectRef:set_pos()` teleporte l'objet et force un
envoi immediat de sa position au client **sans interpolation**
(`LuaEntitySAO::setPos` appelle `sendPosition(false, true)`) : l'appeler a
chaque pas de simulation, que ce soit sur le joueur ou sur une entite,
produit donc des a-coups constants. La bonne API pour un suivi continu est
`ObjectRef:move_to(pos, true)`, concue par le moteur pour des "transitions
visuellement fluides" (l'entite est interpolee normalement entre deux
positions envoyees). On deplace donc une entite Lua invisible
("camera_rig", sans collision) via `move_to`, et on y attache le joueur :
sa vue herite de ce mouvement interpole.

### Assemblage en 27 nodes

Le cube n'est **pas** une seule entite dont la maille visuelle serait etiree
a 3x3x3 : une texture unique etiree sur toute la face donnerait un rendu
flou au lieu de nodes distincts. C'est a la place un assemblage de **27
petites entites decoratives** (`hexapod_v6:block`, plus une variante
`hexapod_v6:block_front` pour le node central de la face avant, qui indique
la direction d'avancee), chacune de la **meme taille qu'un vrai node de la
carte** (comme `default:stone`, 1x1x1), attachees en grille 3x3x3 a l'entite
physique invisible (`hexapod_v6:pod`) qui porte seule la collision et le
pilotage.

**Piege rencontre en le construisant :** `hexapod_v6:pod` doit garder une
`visual_size` **non nulle** (`{1,1,1}`), meme s'il est invisible. Les 27
blocs lui sont attaches (`set_attach`) : cote moteur, l'echelle du parent se
propage **multiplicativement** a tous ses descendants dans le graphe de
scene. Une echelle nulle sur le parent (comme pour `hexapod_v6:camera_rig`,
qui lui n'a rien d'attache) aurait donc rendu les 27 blocs invisibles,
quelle que soit leur propre `visual_size` -- effectivement observe en jeu
lors du premier essai. La solution, deja utilisee par `hexapod_v3:leg_pivot`
pour la meme raison : une echelle neutre (`{1,1,1}`, qui ne deforme donc pas
les decalages des blocs attaches, exprimes en unites de noeuds absolues) et
une texture reellement transparente (alpha nul) pour le rendre invisible
sans toucher a son echelle.

### Tete et corps

Le cube pilotable (`hexapod_v6:pod`) est la **tete**. `hexapod_v6.body_count`
(7 par defaut -- voir "Pattes" ci-dessous pour la raison de ce nombre)
cubes **identiques** (meme assemblage 3x3x3 de 27 nodes, memes 9 relais de
collision chacun -- voir "Collision" ci-dessous) sont ajoutes a la queue
leu leu derriere elle, colles face contre face (aucun espace entre deux
cubes consecutifs, cf. `hexapod_v6.segment_z`) : c'est le **corps**.

Le corps est purement visuel et solide : ces cubes ne sont **pas**
pilotables individuellement (pas de clic droit propre, pas de camera
dediee) -- ils suivent la tete (position ET rotation) comme un seul objet,
exactement comme le "train arriere" decoratif de `hexapod_v3`, mais en
gardant en plus l'integralite de la collision sur chaque segment.

Concretement, `hexapod_v6.spawn_blocks` et `hexapod_v6.spawn_colliders`
ne construisent plus qu'un seul segment (la tete) mais
`1 + hexapod_v6.body_count` (8 par defaut) : 216 blocs visuels et 72 relais
de collision au total, tous attaches/repositionnes par rapport a la MEME
entite invisible (`hexapod_v6:pod`), avec un simple decalage en Z
supplementaire par segment (`hexapod_v6.segment_z`).

**Collision : 9 relais par colonne et par segment (tete + corps), plutot
qu'une seule boite sur `pod`.** `hexapod_v6:pod` lui-meme est **non
physique** (`physical = false`) : il ne sert plus qu'au clic
(piloter/descendre), via une `selectionbox` explicite couvrant la tete.
La collision reelle est geree par des entites independantes
(`hexapod_v6:collider`), 9 par segment (une par colonne verticale de la
grille 3x3, x/z), repositionnees chaque pas sur leur colonne en tenant
compte de la position et du yaw courants du cube (meme logique que les
relais de collision des pattes de `hexapod_v3`, PAS attachees : un objet
attache n'a, cote serveur, pas d'autre position que celle de son parent,
cf. `LuaEntitySAO::step`).

**Piege rencontre : `set_properties` recalcule `selectionbox` par
defaut.** Chaque relais utilise la MEME entite generique
`hexapod_v6:collider` (declaree avec une `collisionbox` et une
`selectionbox` nulles), a laquelle `hexapod_v6.spawn_colliders` applique
ensuite sa propre `collisionbox` (colonne ou patte) via `set_properties`.
Appeler `set_properties({collisionbox = ...})` SANS repreciser
`selectionbox` dans le meme appel fait que le moteur recalcule cette
derniere par defaut a partir de la NOUVELLE collisionbox (non nulle),
ecrasant la `selectionbox` nulle d'origine : chaque relais redevenait donc
cliquable, avec une grosse `selectionbox`, interceptant les clics droits
destines a `hexapod_v6:pod` (confirme en jeu par le journal serveur :
les clics visaient `hexapod_v6:collider` au lieu du cube, empechant de
piloter en cliquant sur la tete). Solution : repasser explicitement
`selectionbox = {0, 0, 0, 0, 0, 0}` dans le MEME appel a
`set_properties`.

Deux problemes, rencontres successivement en construisant ce design,
justifient de ne PAS se contenter d'une seule boite sur `pod` :

1. **La collisionbox ne tourne jamais avec le yaw.** Le moteur ne fait
   JAMAIS tourner la `collisionbox` d'une entite avec son yaw -- elle reste
   toujours alignee sur les axes du monde, translatee uniquement par sa
   position -- alors que les 27 blocs visuels, eux, heritent bien de la
   rotation du parent (`set_attach`). Avec une seule boite fixe (taille du
   cube, 3x3x3), des que le cube pivotait loin d'un angle multiple de
   90 degres, ses coins visuels depassaient donc de la collisionbox --
   jusqu'a `size/2 * (sqrt(2) - 1)` noeuds au pire cas (45 degres), soit
   environ 0,62 noeud -- et aucune collision ne s'y produisait.

   Premiere tentative : elargir la demi-etendue horizontale (X/Z) de cette
   boite unique a `size/2 * sqrt(2)` (le pire cas a 45 degres), pour
   qu'elle contienne toujours le cube visuel quel que soit son yaw.

2. **Mais l'elargissement de la premiere tentative approchait une seconde
   limite du moteur.** Une entite n'est prise en compte pour la collision
   joueur/objet que si le joueur se trouve a moins d'environ 3,4 noeuds de
   la position PROPRE de cette entite (limite independante de la taille de
   sa collisionbox, cf. `ActiveObjectMgr::getActiveObjects`). Le coin le
   plus eloigne de la boite elargie (en 3D, combinant l'elargissement
   horizontal ET la demi-hauteur du cube) se trouvait a ~3,354 noeuds du
   centre du pod -- a peine sous cette limite (marge de 0,05 noeud
   seulement) : suffisant pour qu'approcher un coin en diagonale (ou un
   coin du cube pivote) passe, en pratique, au-dela de la limite et ne
   bloque plus du tout.

   D'ou le design final, retenu : au lieu d'UNE grosse boite centree sur le
   pod, 9 PETITS relais independants, un par colonne (empreinte 1x1,
   elargie a `block_size/2 * sqrt(2)` pour rester valable a 45 degres, sur
   toute la hauteur du cube). Chaque relais ne couvre que SA PROPRE colonne
   et reste pres de l'endroit qu'il protege (repositionne chaque pas selon
   la rotation reelle) plutot que de rester loin, au centre du cube entier
   -- son propre coin le plus eloigne (~1,8 noeud) reste tres largement
   sous la limite de ~3,4 noeuds (marge de ~1,6 noeud), quelle que soit la
   rotation.

### Pattes

3 paires de pattes (6 au total), **meme forme, meme position et meme
demarche animee que `hexapod_v3`** : chaine "en L" hanche -> femur
(horizontal, s'eloigne du cube) -> genou -> tibia (vertical, descend),
attachees de part et d'autre du 1er, du 4e et du 7e segment de corps (cf.
`hexapod_v6.leg_z`), 2 segments restant donc libres entre deux paires --
meme proportion que le `leg_pair_spacing` (= 3) de `hexapod_v3`.

**Pourquoi 2 segments libres (et non 1) entre deux paires.** La tibia de
chaque patte depasse d'un cube entier (`hexapod_v6.size`) vers l'avant par
rapport a sa propre hanche (meme construction relative que `hexapod_v3`,
juste a l'echelle d'un cube plutot que d'un node). Avec seulement 1
segment libre entre deux paires (`hexapod_v6.body_count = 5`, pattes sur
le 1er/3e/5e segment), cette avancee ne laissait plus qu'un coin de cube
de marge entre la tibia d'une patte et la hanche de la suivante. Porter
`hexapod_v6.body_count` a 7 (2 segments libres, pattes sur le 1er/4e/7e)
donne un ecart reel EXACT de 1 cube entre la tibia d'une patte et la
hanche de la suivante (verifie par calcul : l'ecart entre deux hanches
est de 3 segments = 9 noeuds ; en retranchant le cube de la tibia qui
avance et le demi-cube de chaque cote, il reste exactement `size` = 3
noeuds de marge).

**Meme taille et meme construction que la tete et le corps.** Chaque piece
de patte (hanche, femur, genou, tibia) fait **3x3x3 nodes**
(`hexapod_v6.size`, pas la taille d'un simple node) et, comme la tete et le
corps, est composee d'un assemblage de **27 blocs** plutot que d'une seule
maille etiree : hanche et genou utilisent `hexapod_v6:block_joint`
(texture de jointure) ; femur et tibia reutilisent `hexapod_v6:block`
(texture du corps).

### Demarche animee

Les pattes bougent en marchant/pivotant, exactement comme
`hexapod_v3.update_legs` : demarche **"tripode"**, les 6 pattes reparties
en 2 groupes de 3 qui alternent balancement (patte levee, avance) et appui
(patte au sol, recule) -- quand un groupe balance, l'autre est en appui, et
inversement (`hexapod_v6.spawn_legs` alterne le groupe paire par paire et
cote par cote, comme `hexapod_v3.spawn_legs`, pour que deux pattes
voisines ne soient jamais dans le meme groupe).

**Construction en chaine, comme `hexapod_v3`.** Chaque piece de patte
(hanche, chaque segment de femur, genou, chaque segment de tibia) est une
entite-ancre invisible (`hexapod_v6:leg_anchor`) portant ses 27 blocs, et
chaque ancre est un veritable enfant (`set_attach`) de la precedente --
pour qu'une rotation entraine bien tout ce qui est attache en dessous.
Contrairement au reste du corps (attache directement, en un seul niveau,
a `hexapod_v6:pod`), cette chaine est necessaire ICI car deux points de la
patte doivent pouvoir tourner independamment :

- un **pivot de hanche** (`hip_pivot`, colle exactement sur la hanche,
  decalage nul) dont la rotation Y (horizontale) balaie tout le
  femur+genou+tibia attaches en dessous -- la hanche elle-meme ne bouge
  jamais ;
- le **genou** lui-meme sert de pivot pour le tibia (rotation X,
  verticale) -- pas besoin d'un pivot separe, puisque rien d'autre que le
  tibia ne depend de sa position au repos.

`hip_pivot` et `genou` etant attaches, `set_rotation()` est ignore sur eux
(cf. lua_api.md) : leur rotation est reanimee chaque pas en rappelant
`set_attach` avec le meme decalage de position mais une nouvelle rotation
(`hexapod_v6.update_legs`) -- amplitude de balayage de la hanche
`hexapod_v6.leg_hip_swing_deg` (25 degres), amplitude de levee du genou
`hexapod_v6.leg_knee_lift_deg` (35 degres), vitesse de phase
`hexapod_v6.leg_gait_speed` (1 cycle/seconde) -- valeurs identiques a
`hexapod_v3`. La levee du genou n'a lieu que sur la moitie "avant" du
cycle (phase de balancement) ; il reste a plat pendant la moitie "arriere"
(phase d'appui), pour que la patte pousse au sol sans se relever.

**La collision, elle, reste au repos.** Comme `hexapod_v3`, les relais de
collision des pattes (`hexapod_v6.leg_piece_offsets`, voir "Collision"
ci-dessous) NE suivent PAS cette animation -- ils restent a la position de
repos (sans balancement ni levee), un choix deja fait par `hexapod_v3` et
repris ici a l'identique.

**Son de pas.** Un son (`hexapod_v6.footstep_sound`, 3 variantes reutilisees
du "pas sur metal" du mod `default`) est joue des qu'un groupe de pattes
passe de leve a pose (meme condition, `sin(phase) > 0`, que pour la levee
du genou ci-dessus). Un seul appel par GROUPE -- pas par patte individuelle
-- puisque les 3 pattes d'un groupe se posent toujours simultanement : un
son par patte aurait produit 3 copies exactement superposees.

**Collision : 9 relais par colonne et par piece, comme un segment de
corps/tete.** A cette taille (3x3x3), une seule boite de collision par
piece se heurterait exactement aux memes deux problemes que ceux
rencontres et resolus pour le corps (voir "Collision" plus haut) :
la collisionbox ne tourne pas avec le yaw, et l'elargir pour compenser
approche trop pres de la limite de portee du moteur (~3,4 noeuds). Chaque
piece de patte est donc, elle aussi, decoupee en 9 relais par colonne
(`hexapod_v6.column_offsets`, decale par la position de la piece) --
378 relais de pattes (42 pieces x 9) s'ajoutent ainsi aux 72 de la tete et
du corps (8 segments x 9), 450 au total, chacun avec une marge de ~1,6
noeud sous la limite du moteur, quelle que soit la rotation.

**Placement au sol.** Le hexapod est pose (`on_place`) a une hauteur de
`hexapod_v6.leg_drop` au-dessus du point clique, et non plus
`hexapod_v6.size / 2` : `leg_drop` mesure la distance entre le centre d'un
cube (hauteur de la hanche) et la face inferieure du dernier cube de
tibia, exactement comme `hexapod_v3.leg_drop` (meme formule, avec
`hexapod_v6.size` a la place de `tail_size`). Sans ca, c'est le dessous du
cube tete/corps qui aurait touche le sol, laissant les pattes s'enfoncer
dedans.

### A propos des touches "flechees"

Luanti n'expose aux mods que l'etat des touches deja associees aux actions
de deplacement du joueur (`up`/`down`/`left`/`right`), quelles que soient les
touches physiques choisies dans **Parametres > Touches**. Par defaut, ce
sont Z/Q/S/D (ou W/A/S/D en QWERTY). Pour piloter le hexapod avec les
fleches directionnelles du clavier, il suffit de rebinder ces 4 actions sur
les fleches Haut/Bas/Gauche/Droite dans le menu des touches ; le mod suit
alors exactement ces touches.

## Installation

1. Copier le dossier `hexapod_v6` dans le repertoire `mods` du monde (ou
   dans le dossier `mods` global de Luanti).
2. Activer le mod dans la fenetre "Configurer le monde" du menu principal,
   ou ajouter la ligne suivante dans `world.mt` :

   ```
   load_mod_hexapod_v6 = true
   ```

## Utilisation

1. Obtenir l'item `hexapod_v6:pod` (inventaire creatif ou
   `/giveme hexapod_v6:pod`).
2. Le poser quelque part : l'entite pilotable apparait.
3. Faire un clic droit dessus pour prendre les commandes : la camera se
   place automatiquement en vue exterieure, centree sur le hexapod.
4. Utiliser les touches de deplacement (fleches, si rebindees comme
   explique ci-dessus) pour avancer, reculer et pivoter, et la souris pour
   regarder librement autour du hexapod.
5. Refaire un clic droit dessus pour lacher les commandes et retrouver son
   propre deplacement.

## Structure du mod

```
hexapod_v6/
├── init.lua                          # entites, item de pose, logique de pilotage et de camera
├── mod.conf                          # declaration du mod
├── textures/
│   ├── hexapod_v6_node.png           # texture des blocs du cube (corps/tete/femur/tibia)
│   ├── hexapod_v6_node_front.png     # texture du bloc central de la face avant
│   ├── hexapod_v6_joint.png          # texture des blocs de jointure (hanche/genou)
│   └── hexapod_v6_invisible.png      # texture transparente (pod, camera_rig, leg_anchor)
├── sounds/
│   ├── hexapod_v6_footstep.{1,2,3}.ogg  # son de pas (3 variantes)
│   ├── hexapod_v6_engine.ogg            # son de moteur (avance)
│   └── hexapod_v6_turn.ogg              # son de direction (pivote)
└── README.md
```
