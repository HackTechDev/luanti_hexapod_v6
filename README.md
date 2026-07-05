# hexapod_v6

Mod Luanti (Minetest) qui ajoute un hexapod pilotable au clavier de facon
**continue et fluide**, observe depuis une **camera exterieure a la
troisieme personne**, contrairement a :

- `hexapod_v1` : deplacement pas a pas via un formspec ;
- `hexapod_v2` : deplacement continu, mais le joueur est *attache* sur le
  hexapod (camera a la premiere personne, "dans" le node).

## Fonctionnement

- Le mod ajoute un objet `hexapod_v6:pod` : un cube de **3x3x3 nodes** (des
  entites, pas des nodes de la carte, pour un deplacement fluide hors grille
  voxel), compose de **27 pieces individuelles** de la taille d'un vrai node
  (voir "Assemblage en 27 nodes" ci-dessous). C'est la **tete** : 5 cubes
  identiques (le **corps**) la suivent a la queue leu leu (voir "Tete et
  corps" ci-dessous).
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
(5 par defaut) cubes **identiques** (meme assemblage 3x3x3 de 27 nodes,
memes 9 relais de collision chacun -- voir "Collision" ci-dessous) sont
ajoutes a la queue leu leu derriere elle, colles face contre face (aucun
espace entre deux cubes consecutifs, cf. `hexapod_v6.segment_z`) : c'est le
**corps**.

Le corps est purement visuel et solide : ces cubes ne sont **pas**
pilotables individuellement (pas de clic droit propre, pas de camera
dediee) -- ils suivent la tete (position ET rotation) comme un seul objet,
exactement comme le "train arriere" decoratif de `hexapod_v3`, mais en
gardant en plus l'integralite de la collision sur chaque segment.

Concretement, `hexapod_v6.spawn_blocks` et `hexapod_v6.spawn_colliders`
ne construisent plus qu'un seul segment (la tete) mais
`1 + hexapod_v6.body_count` (6 par defaut) : 162 blocs visuels et 54 relais
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
│   ├── hexapod_v6_node.png           # texture des 27 blocs du cube
│   ├── hexapod_v6_node_front.png     # texture du bloc central de la face avant
│   └── hexapod_v6_invisible.png      # texture transparente (pod, camera_rig)
└── README.md
```
