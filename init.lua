-- hexapod_v6
-- Fournit une entite "hexapod_v6:pod" pilotable au clavier de facon continue
-- et fluide (Haut/Bas avancent ou reculent, Gauche/Droite pivotent), avec une
-- camera "troisieme personne" : le joueur n'est jamais colle sur le node, il
-- l'observe depuis l'exterieur. Sa camera reste en permanence centree sur le
-- node et le suit lors de ses deplacements, tout en gardant le controle
-- libre du regard (souris) ; en revanche il perd son propre deplacement
-- (ZQSD/fleches, saut, gravite) tant qu'il pilote le hexapod.
--
-- Important : le cube n'est PAS une seule entite dont la maille visuelle est
-- etiree a 3x3x3 (une texture unique, etiree sur toute la face, rendrait un
-- aspect flou au lieu de nodes distincts) -- c'est un assemblage de 27
-- petites entites ("hexapod_v6:block"), chacune de la MEME taille qu'un
-- vrai node de la carte (comme `default:stone`, cf. hexapod_v6.spawn_blocks),
-- attachees en grille 3x3x3 a l'entite physique invisible qui porte la
-- collision et le pilotage.
--
-- Le cube pilotable ("hexapod_v6:pod") est la "tete" ; hexapod_v6.body_count
-- (5 par defaut) cubes IDENTIQUES sont ajoutes a la queue leu leu derriere
-- elle, colles face contre face : c'est le "corps" (voir
-- hexapod_v6.segment_z). Chaque segment de corps garde l'integralite de la
-- collision (9 relais independants, comme la tete elle-meme, voir
-- hexapod_v6.relay_offsets), mais n'est pas pilotable individuellement :
-- tout suit la tete comme un seul objet.
--
-- Note technique (camera) : la camera n'est ni le joueur teleporte a chaque
-- pas, ni une entite deplacee via `set_pos()` (les deux forcent une
-- correction de position sans interpolation cote client, donc des a-coups).
-- On deplace une entite Lua invisible ("camera_rig") via `move_to(pos,
-- true)`, l'API prevue par le moteur pour un suivi visuellement fluide, et
-- on y attache le joueur : sa vue herite alors de ce mouvement interpole.

hexapod_v6 = {}

-- Nombre de nodes par cote du cube.
hexapod_v6.blocks_per_side = 3

-- Taille d'un node individuel, en noeuds -- IDENTIQUE a un vrai node de la
-- carte tel que `default:stone` (1x1x1). C'est ce qui distingue
-- l'assemblage de hexapod_v6 d'un simple cube etire : chaque piece visible
-- a exactement la taille d'un node standard.
hexapod_v6.block_size = 1

-- Taille totale du cube (cote), en noeuds.
hexapod_v6.size = hexapod_v6.blocks_per_side * hexapod_v6.block_size

-- ---------------------------------------------------------------------
-- "Tete" et "corps" : une file de cubes identiques derriere le pod
-- ---------------------------------------------------------------------
-- Le cube pilotable ("hexapod_v6:pod") est la "tete". `hexapod_v6.body_count`
-- cubes IDENTIQUES (meme assemblage 3x3x3 de 27 nodes, memes 9 relais de
-- collision chacun) sont ajoutes a la queue leu leu derriere elle, colles
-- face contre face (aucun espace entre deux cubes consecutifs) : c'est le
-- "corps". Purement visuel et solide -- ces cubes ne sont pas pilotables
-- individuellement, ils suivent la tete (position ET rotation) comme un
-- seul objet.
hexapod_v6.body_count = 5

-- Decalage en Z (repere du corps a yaw = 0) de chaque segment de la file :
-- le premier ([1]) est la tete elle-meme (decalage nul, cf.
-- hexapod_v6.spawn_blocks / hexapod_v6.spawn_colliders qui l'utilisent
-- directement pour repositionner tout le reste), les suivants ([2] a
-- [1 + body_count]) sont les segments de corps, chacun recule d'un cube
-- entier (`hexapod_v6.size`) de plus que le precedent.
hexapod_v6.segment_z = {}
for seg = 0, hexapod_v6.body_count do
	table.insert(hexapod_v6.segment_z, -hexapod_v6.size * seg)
end

-- ---------------------------------------------------------------------
-- Collision : relais par colonne (voir hexapod_v6:collider plus bas)
-- ---------------------------------------------------------------------
-- Le moteur ne fait JAMAIS tourner la collisionbox d'une entite avec son
-- yaw (elle reste toujours alignee sur les axes du monde, translatee
-- uniquement par sa position) -- alors que les 27 blocs visuels, eux,
-- tournent bien (ils heritent de la rotation du parent via `set_attach`).
--
-- Premiere tentative (abandonnee) : une SEULE collisionbox sur le pod,
-- elargie a size/2 * sqrt(2) (le pire cas a 45 degres) pour contenir le
-- cube visuel quel que soit son yaw. Ca resolvait bien le probleme de
-- rotation, mais introduisait un second probleme : une entite n'est prise
-- en compte pour la collision joueur/objet que si le joueur se trouve a
-- moins d'environ 3,4 noeuds de la position PROPRE de cette entite (limite
-- du moteur indep. de la taille de sa collisionbox, cf.
-- `ActiveObjectMgr::getActiveObjects`) -- et le coin le plus eloigne de
-- cette boite agrandie (en 3D, combinant l'elargissement horizontal ET la
-- demi-hauteur du cube) se trouvait a ~3,354 noeuds du centre du pod, donc
-- a peine sous cette limite (marge de 0,05 noeud) : suffisant pour qu'en
-- pratique, approcher un coin en diagonale (ou un coin du cube pivote)
-- passe intermittemment au-dela de la limite et ne bloque plus du tout
-- (observe en jeu).
--
-- Solution retenue (meme principe que les relais de pattes de
-- hexapod_v3) : au lieu d'UNE grosse boite centree sur le pod, on utilise
-- 9 PETITS relais independants, un par colonne verticale de la grille 3x3
-- (x,z), repositionnes chaque pas selon la rotation reelle du cube (voir
-- hexapod_v6.reposition_colliders). Chaque relais ne couvre que SA PROPRE
-- colonne (empreinte 1x1, elargie a block_size/2 * sqrt(2) pour rester
-- valable a 45 degres) sur toute la hauteur du cube -- son propre coin le
-- plus eloigne (~1,8 noeud, voir calcul plus bas) reste tres largement
-- sous la limite de ~3,4 noeuds, quelle que soit la rotation, puisque
-- chaque relais est repositionne pres de l'endroit qu'il protege plutot
-- que de rester loin, au centre du cube entier.
hexapod_v6.column_half_horizontal = (hexapod_v6.block_size / 2) * math.sqrt(2)

-- Decalage local {x, z} (repere du corps a yaw = 0) de chacune des 9
-- colonnes verticales de la grille 3x3 d'UN SEUL cube (tete ou segment de
-- corps).
hexapod_v6.column_offsets = {}
do
	local half_span = (hexapod_v6.blocks_per_side - 1) / 2
	for xi = 0, hexapod_v6.blocks_per_side - 1 do
		for zi = 0, hexapod_v6.blocks_per_side - 1 do
			table.insert(hexapod_v6.column_offsets, {
				x = (xi - half_span) * hexapod_v6.block_size,
				z = (zi - half_span) * hexapod_v6.block_size,
			})
		end
	end
end

-- Decalage local {x, z} de CHAQUE colonne de CHAQUE segment (tete +
-- hexapod_v6.body_count segments de corps) : hexapod_v6.column_offsets,
-- decale en Z par hexapod_v6.segment_z pour chaque segment -- 9 * (1 +
-- body_count) relais au total. Utilise par hexapod_v6.spawn_colliders /
-- hexapod_v6.reposition_colliders pour que chaque segment garde sa propre
-- collision complete (memes 9 relais que la tete).
hexapod_v6.relay_offsets = {}
for _, seg_z in ipairs(hexapod_v6.segment_z) do
	for _, col in ipairs(hexapod_v6.column_offsets) do
		table.insert(hexapod_v6.relay_offsets, { x = col.x, z = col.z + seg_z })
	end
end

-- Vitesses de deplacement du hexapod
hexapod_v6.forward_speed = 4          -- noeuds par seconde
hexapod_v6.turn_speed = math.rad(90)  -- radians par seconde

-- Distance a laquelle la camera est maintenue derriere le regard du joueur,
-- de sorte que le hexapod reste toujours exactement au centre de la vue,
-- quelle que soit la direction observee.
hexapod_v6.camera_distance = 6

-- Ensemble des hexapods actifs (cle = luaentity), utilise pour detacher
-- proprement un joueur qui se deconnecte pendant qu'il pilote.
hexapod_v6.pods = {}

-- Physique (vitesse, saut, gravite) sauvegardee par joueur pendant qu'il
-- pilote, pour la restaurer telle quelle a la fin.
hexapod_v6.saved_physics = {}

-- Calcule la position (position du pied du joueur) a laquelle la camera
-- doit se trouver pour que `pod_pos` soit exactement au centre de la vue,
-- a distance fixe, selon la direction actuellement regardee par le joueur.
function hexapod_v6.compute_camera_pos(pod_pos, look_dir, player)
	local eye_pos = vector.subtract(pod_pos, vector.multiply(look_dir, hexapod_v6.camera_distance))

	local props = player:get_properties()
	local eye_height = (props and props.eye_height) or 1.625
	eye_pos.y = eye_pos.y - eye_height

	return eye_pos
end

-- Deplace la rig-camera du hexapod pour que celui-ci reste centre dans la
-- vue du joueur qui le pilote.
--
-- Important : on n'utilise PAS `set_pos()` a chaque pas. Cote moteur,
-- `ObjectRef:set_pos()` teleporte l'entite ET force un envoi immediat de sa
-- position au client SANS interpolation (voir `LuaEntitySAO::setPos`, qui
-- appelle `sendPosition(false, true)` -- le premier `false` desactive
-- l'interpolation cote client) : appeler ca a chaque pas de simulation
-- produit donc des a-coups constants. `move_to(pos, true)` est concu par le
-- moteur precisement pour des "transitions visuellement fluides" : la
-- position cible est mise a jour en continu et le client interpole
-- normalement entre deux positions envoyees.
function hexapod_v6.update_camera(self, player)
	local look_dir = player:get_look_dir()
	local pod_pos = self.object:get_pos()
	local target = hexapod_v6.compute_camera_pos(pod_pos, look_dir, player)
	self.camera_rig:move_to(target, true)
end

-- Construit l'assemblage visuel complet : pour la tete ET chaque segment de
-- corps (hexapod_v6.segment_z), une grille de `hexapod_v6.blocks_per_side`^3
-- (27 par defaut) petites entites, chacune de la taille d'un node standard
-- (`hexapod_v6.block_size`), attachees (`set_attach`, decalage fixe) a
-- l'entite physique invisible ("hexapod_v6:pod"). Un seul de ces blocs --
-- celui du centre de la face avant (+Z, cf. le commentaire sur l'ordre des
-- faces plus bas) DE LA TETE (premier segment, decalage nul) -- utilise
-- l'entite "hexapod_v6:block_front", identique sauf sur sa propre face
-- exterieure, pour indiquer visuellement la direction d'avancee. Les
-- segments de corps n'ont pas de bloc distinct : uniquement
-- "hexapod_v6:block".
--
-- Note : la position passee a `set_attach` doit etre multipliee par 10 par
-- rapport aux coordonnees monde (cf. section "Attachments" de lua_api.md).
function hexapod_v6.spawn_blocks(self)
	self.blocks = {}
	local pod_object = self.object
	local pod_pos = pod_object:get_pos()
	local half_span = (hexapod_v6.blocks_per_side - 1) / 2  -- decalage (en nodes) du 1er/dernier bloc au centre

	for seg_index, seg_z in ipairs(hexapod_v6.segment_z) do
		for xi = 0, hexapod_v6.blocks_per_side - 1 do
			for yi = 0, hexapod_v6.blocks_per_side - 1 do
				for zi = 0, hexapod_v6.blocks_per_side - 1 do
					local offset = {
						x = (xi - half_span) * hexapod_v6.block_size,
						y = (yi - half_span) * hexapod_v6.block_size,
						z = (zi - half_span) * hexapod_v6.block_size + seg_z,
					}
					local is_front = (seg_index == 1)
						and (xi == math.floor(hexapod_v6.blocks_per_side / 2))
						and (yi == math.floor(hexapod_v6.blocks_per_side / 2))
						and (zi == hexapod_v6.blocks_per_side - 1)
					local entity_name = is_front and "hexapod_v6:block_front" or "hexapod_v6:block"

					local block = minetest.add_entity(pod_pos, entity_name)
					block:set_attach(pod_object, "",
						{ x = offset.x * 10, y = offset.y * 10, z = offset.z * 10 },
						{ x = 0, y = 0, z = 0 })
					table.insert(self.blocks, block)
				end
			end
		end
	end
end

-- Cree les relais de collision -- 9 par segment (un par colonne, voir
-- hexapod_v6.column_offsets), pour la tete ET chaque segment de corps, soit
-- hexapod_v6.relay_offsets au total. PAS attaches (`set_attach`) : un objet
-- attache n'a, cote serveur, pas d'autre position que celle de son parent
-- (cf. LuaEntitySAO::step) -- ils sont donc repositionnes chaque pas "a la
-- main" (voir hexapod_v6.reposition_colliders), comme les relais de
-- collision des pattes de hexapod_v3.
function hexapod_v6.spawn_colliders(self)
	self.colliders = {}
	local pod_pos = self.object:get_pos()
	for _, offset in ipairs(hexapod_v6.relay_offsets) do
		table.insert(self.colliders,
			minetest.add_entity(vector.add(pod_pos, { x = offset.x, y = 0, z = offset.z }),
				"hexapod_v6:collider"))
	end
end

-- Repositionne chaque relais de collision sur sa colonne (tete ou segment
-- de corps), en tenant compte de la position ET du yaw courants du cube
-- (le decalage local {x, z} de chaque colonne est tourne en consequence).
-- "avant" = minetest.yaw_to_dir(yaw) ; "droite" = son perpendiculaire
-- (verifie a yaw=0 : (1,0,0)). L'axe Y n'a pas besoin d'etre tourne : la
-- rotation se fait uniquement autour de l'axe vertical.
function hexapod_v6.reposition_colliders(self)
	if not self.colliders then
		return
	end
	local pod_pos = self.object:get_pos()
	local yaw = self.object:get_yaw()
	local forward = minetest.yaw_to_dir(yaw)
	local right = { x = math.cos(yaw), y = 0, z = math.sin(yaw) }
	for i, collider in ipairs(self.colliders) do
		local offset = hexapod_v6.relay_offsets[i]
		local world_offset = vector.add(
			vector.multiply(right, offset.x),
			vector.multiply(forward, offset.z))
		collider:set_pos(vector.add(pod_pos, world_offset))
	end
end

function hexapod_v6.start_driving(self, player)
	local name = player:get_player_name()
	self.driver = player
	hexapod_v6.saved_physics[name] = player:get_physics_override()
	player:set_physics_override({ speed = 0, jump = 0, gravity = 0 })

	local look_dir = player:get_look_dir()
	local pod_pos = self.object:get_pos()
	local target = hexapod_v6.compute_camera_pos(pod_pos, look_dir, player)
	self.camera_rig = minetest.add_entity(target, "hexapod_v6:camera_rig")
	player:set_attach(self.camera_rig, "", { x = 0, y = 0, z = 0 }, { x = 0, y = 0, z = 0 })

	minetest.chat_send_player(name,
		"[Hexapod] Vous prenez les commandes du cube. Clic droit pour descendre.")
end

function hexapod_v6.stop_driving(self, player)
	local name = player:get_player_name()
	local saved = hexapod_v6.saved_physics[name]
	if saved then
		player:set_physics_override(saved)
		hexapod_v6.saved_physics[name] = nil
	end
	if self.driver == player then
		self.driver = nil
	end
	player:set_detach()
	if self.camera_rig then
		self.camera_rig:remove()
		self.camera_rig = nil
	end
	self.object:set_velocity({ x = 0, y = 0, z = 0 })

	minetest.chat_send_player(name, "[Hexapod] Vous quittez le cube.")
end

-- Entite invisible (taille nulle) qui sert de support de camera : le
-- joueur qui pilote un hexapod y est attache, et c'est elle qu'on deplace
-- chaque pas de simulation pour suivre le hexapod. Etant une entite comme
-- une autre, le client l'interpole en douceur entre deux positions.
minetest.register_entity("hexapod_v6:camera_rig", {
	initial_properties = {
		visual = "cube",
		visual_size = { x = 0, y = 0, z = 0 },
		physical = false,
		collide_with_objects = false,
		collisionbox = { 0, 0, 0, 0, 0, 0 },
		pointable = false,
		static_save = false,
		textures = {},
	},
})

-- Node individuel de l'assemblage (voir hexapod_v6.spawn_blocks) : purement
-- decoratif, attache (donc sans collision ni pointabilite propres -- c'est
-- l'entite "hexapod_v6:pod" qui porte la collision et le pilotage pour tout
-- l'assemblage). Meme taille qu'un vrai node de la carte
-- (hexapod_v6.block_size).
minetest.register_entity("hexapod_v6:block", {
	initial_properties = {
		visual = "cube",
		visual_size = { x = hexapod_v6.block_size, y = hexapod_v6.block_size, z = hexapod_v6.block_size },
		textures = {
			"hexapod_v6_node.png", "hexapod_v6_node.png",
			"hexapod_v6_node.png", "hexapod_v6_node.png",
			"hexapod_v6_node.png", "hexapod_v6_node.png",
		},
		physical = false,
		collide_with_objects = false,
		collisionbox = { 0, 0, 0, 0, 0, 0 },
		pointable = false,
		static_save = false,
	},
})

-- Variante du node ci-dessus pour le bloc central de la face avant (+Z) de
-- l'assemblage : identique, sauf sur sa propre face exterieure, qui recoit
-- une texture distincte pour indiquer visuellement la direction d'avancee.
-- Ordre des faces d'un visual "cube" (identique aux tiles des nodes) :
-- +Y (haut), -Y (bas), +X, -X, +Z, -Z. Comme `minetest.yaw_to_dir(0)` vaut
-- (0,0,1), la face +Z est celle qui pointe dans la direction d'avancee a
-- yaw=0 : c'est donc elle qui recoit la texture "avant".
minetest.register_entity("hexapod_v6:block_front", {
	initial_properties = {
		visual = "cube",
		visual_size = { x = hexapod_v6.block_size, y = hexapod_v6.block_size, z = hexapod_v6.block_size },
		textures = {
			"hexapod_v6_node.png", "hexapod_v6_node.png",
			"hexapod_v6_node.png", "hexapod_v6_node.png",
			"hexapod_v6_node_front.png", "hexapod_v6_node.png",
		},
		physical = false,
		collide_with_objects = false,
		collisionbox = { 0, 0, 0, 0, 0, 0 },
		pointable = false,
		static_save = false,
	},
})

-- Relais de collision d'une colonne (voir hexapod_v6.column_offsets) : une
-- entite independante (PAS attachee, voir hexapod_v6.spawn_colliders),
-- repositionnee chaque pas sur sa colonne (hexapod_v6.reposition_colliders).
-- `pointable = true` est essentiel : sans lui la collision joueur/objet ne
-- se declenche jamais (meme verification empirique que
-- `hexapod_v3:leg_collider`). `selectionbox` explicite et nulle : sans
-- elle, un clic droit pres d'un relais viserait ce dernier plutot que le
-- cube (via `hexapod_v6:pod`) ou le sol. Invisible (`visual_size` nulle,
-- sans risque ici car RIEN n'est attache a un collider).
minetest.register_entity("hexapod_v6:collider", {
	initial_properties = {
		visual = "cube",
		visual_size = { x = 0, y = 0, z = 0 },
		textures = {},
		collisionbox = {
			-hexapod_v6.column_half_horizontal, -hexapod_v6.size / 2, -hexapod_v6.column_half_horizontal,
			hexapod_v6.column_half_horizontal, hexapod_v6.size / 2, hexapod_v6.column_half_horizontal,
		},
		selectionbox = { 0, 0, 0, 0, 0, 0 },
		physical = true,
		collide_with_objects = true,
		pointable = true,
		static_save = false,
	},
})

-- Entite invisible qui porte le pilotage et le clic de tout l'assemblage
-- (voir hexapod_v6.spawn_blocks pour la partie visible, et
-- hexapod_v6:collider pour la collision reelle, geree par 9 relais
-- independants plutot que par cette entite elle-meme -- voir plus haut
-- pourquoi). `physical = false` : elle ne bloque donc pas le joueur
-- elle-meme (les colliders s'en chargent), mais garde une `selectionbox`
-- explicite couvrant tout le cube pour rester cliquable (piloter/descendre).
--
-- IMPORTANT : contrairement a "hexapod_v6:camera_rig" (rien ne lui est
-- attache), `visual_size` ne doit PAS etre nul ici. Les 27 blocs sont de
-- veritables enfants (`set_attach`) de cette entite dans le graphe de
-- scene : l'echelle du parent s'y propage MULTIPLICATIVEMENT a tous ses
-- descendants (comme documente sur `hexapod_v3:leg_pivot`, meme mecanisme)
-- -- une echelle nulle sur le parent aurait donc rendu les 27 blocs
-- invisibles, quelle que soit leur propre `visual_size` (verifie en jeu :
-- le cube etait completement invisible avec `visual_size = {0,0,0}` ici).
-- On utilise donc une echelle neutre ({1,1,1}, qui ne deforme donc pas les
-- decalages des blocs attaches, exprimes en unites de noeuds) et une
-- texture reellement transparente (alpha nul) pour le rendre invisible
-- sans toucher a son echelle -- exactement la meme astuce que pour
-- `hexapod_v3:leg_pivot`.
minetest.register_entity("hexapod_v6:pod", {
	initial_properties = {
		visual = "cube",
		visual_size = { x = 1, y = 1, z = 1 },
		textures = {
			"hexapod_v6_invisible.png", "hexapod_v6_invisible.png",
			"hexapod_v6_invisible.png", "hexapod_v6_invisible.png",
			"hexapod_v6_invisible.png", "hexapod_v6_invisible.png",
		},
		collisionbox = {
			-hexapod_v6.size / 2, -hexapod_v6.size / 2, -hexapod_v6.size / 2,
			hexapod_v6.size / 2, hexapod_v6.size / 2, hexapod_v6.size / 2,
		},
		selectionbox = {
			-hexapod_v6.size / 2, -hexapod_v6.size / 2, -hexapod_v6.size / 2,
			hexapod_v6.size / 2, hexapod_v6.size / 2, hexapod_v6.size / 2,
		},
		physical = false,
		collide_with_objects = false,
		pointable = true,
		static_save = true,
	},

	driver = nil,
	camera_rig = nil,
	blocks = nil,     -- assemblage visuel (voir hexapod_v6.spawn_blocks)
	colliders = nil,  -- relais de collision par colonne (voir hexapod_v6:collider)

	on_activate = function(self)
		self.object:set_acceleration({ x = 0, y = 0, z = 0 })
		hexapod_v6.pods[self] = true
		hexapod_v6.spawn_blocks(self)
		hexapod_v6.spawn_colliders(self)
	end,

	on_deactivate = function(self)
		if self.driver and self.driver:is_player() then
			hexapod_v6.stop_driving(self, self.driver)
		end
		if self.blocks then
			for _, block in ipairs(self.blocks) do
				block:remove()
			end
			self.blocks = nil
		end
		if self.colliders then
			for _, collider in ipairs(self.colliders) do
				collider:remove()
			end
			self.colliders = nil
		end
		hexapod_v6.pods[self] = nil
	end,

	on_rightclick = function(self, clicker)
		if not clicker or not clicker:is_player() then
			return
		end

		if self.driver then
			if self.driver == clicker then
				hexapod_v6.stop_driving(self, clicker)
			else
				minetest.chat_send_player(clicker:get_player_name(),
					"[Hexapod] Ce hexapod est deja pilote par quelqu'un d'autre.")
			end
			return
		end

		hexapod_v6.start_driving(self, clicker)
	end,

	on_step = function(self, dtime)
		local driver = self.driver
		if not driver or not driver:is_player() then
			self.driver = nil
			hexapod_v6.reposition_colliders(self)
			return
		end

		local ctrl = driver:get_player_control()
		local yaw = self.object:get_yaw()

		if ctrl.left then
			yaw = yaw + hexapod_v6.turn_speed * dtime
		end
		if ctrl.right then
			yaw = yaw - hexapod_v6.turn_speed * dtime
		end
		self.object:set_yaw(yaw)

		local dir = minetest.yaw_to_dir(yaw)
		local vel = { x = 0, y = 0, z = 0 }
		if ctrl.up then
			vel = vector.multiply(dir, hexapod_v6.forward_speed)
		elseif ctrl.down then
			vel = vector.multiply(dir, -hexapod_v6.forward_speed)
		end
		self.object:set_velocity(vel)

		hexapod_v6.update_camera(self, driver)
		hexapod_v6.reposition_colliders(self)
	end,
})

minetest.register_craftitem("hexapod_v6:pod", {
	description = "Hexapod (camera exterieure a la troisieme personne)",
	inventory_image = "hexapod_v6_node.png",
	on_place = function(itemstack, placer, pointed_thing)
		if pointed_thing.type ~= "node" then
			return itemstack
		end

		-- +size/2 pose le cube au ras du sol (son centre est a mi-hauteur).
		local pos = vector.add(pointed_thing.above, { x = 0, y = hexapod_v6.size / 2, z = 0 })
		minetest.add_entity(pos, "hexapod_v6:pod")

		minetest.chat_send_player(placer:get_player_name(),
			string.format("[Hexapod] Cube pose en (%.1f, %.1f, %.1f).", pos.x, pos.y, pos.z))

		if not minetest.settings:get_bool("creative_mode") then
			itemstack:take_item()
		end
		return itemstack
	end,
})

minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	for pod in pairs(hexapod_v6.pods) do
		if pod.driver == player then
			pod.driver = nil
			if pod.camera_rig then
				pod.camera_rig:remove()
				pod.camera_rig = nil
			end
		end
	end
	hexapod_v6.saved_physics[name] = nil
end)
