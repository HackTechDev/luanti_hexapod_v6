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
  (voir "Assemblage en 27 nodes" ci-dessous).
- Un clic droit sur un bloc pose l'item `hexapod_v6:pod` qui fait apparaitre
  l'entite pilotable a cet endroit, avec un message de confirmation indiquant
  ses coordonnees.
- Un clic droit sur le cube prend les commandes (avec un message de
  confirmation). Un second clic droit du meme joueur les relache (idem).

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

**Collision :** une seule `collisionbox`, sur l'entite invisible `pod`,
couvre l'intergralite du volume 3x3x3 (aucun trou, contrairement aux pattes
de `hexapod_v3` qui depassaient du corps). Les 27 blocs decoratifs n'ont
volontairement pas de collision propre. Une seule boite suffit ici (pas
besoin de la decouper en plusieurs relais comme pour les pattes de
`hexapod_v3`) car le cube entier reste petit : sa demi-diagonale
(~2,6 noeuds) reste bien en deca de la limite de ~3,4 noeuds au-dela de
laquelle le moteur ignore un objet pour la collision joueur/objet (limite
mesuree depuis la position PROPRE de l'objet, cf.
`ActiveObjectMgr::getActiveObjects`).

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
