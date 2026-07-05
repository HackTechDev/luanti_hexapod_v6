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
-- hexapod_v6.collider_specs), mais n'est pas pilotable individuellement :
-- tout suit la tete comme un seul objet.
--
-- 3 paires de pattes (6 au total, meme forme et position que hexapod_v3)
-- sont attachees de part et d'autre d'un segment de corps sur deux (voir
-- hexapod_v6.leg_piece_offsets) : chaine hanche -> femur -> genou -> tibia,
-- chaque piece gardant son propre nom d'entite et sa propre collision.
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
--
-- 7 (et non 5) pour laisser la place aux 3 paires de pattes espacees de 3
-- segments (voir hexapod_v6.leg_z) : la tibia de chaque patte depasse d'un
-- cube entier vers l'avant par rapport a son propre segment (meme
-- construction que hexapod_v3), donc un espacement de seulement 2 segments
-- entre deux paires (comme avec 5 segments de corps) ne laissait qu'un
-- coin de cube de marge entre la tibia d'une patte et la hanche de la
-- suivante -- 7 segments, avec des pattes sur le 1er, le 4e et le 7e,
-- donnent exactement 1 cube de separation entre deux pattes, comme demande
-- (meme proportion que hexapod_v3.leg_pair_spacing = 3).
hexapod_v6.body_count = 7

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

-- ---------------------------------------------------------------------
-- Pattes : 3 paires (6 pattes), meme forme et position que hexapod_v3
-- ---------------------------------------------------------------------
-- Chaine "en L" : corps -> hanche -> femur (horizontal, s'eloigne du
-- corps) -> genou -> tibia (vertical, descend). Chaque piece de patte est
-- de la MEME taille que les cubes de la tete et du corps (hexapod_v6.size,
-- 3x3x3 -- pas la taille d'un simple node), et garde son nom
-- (hanche/femur/genou/tibia) via 4 entites decoratives distinctes
-- ("hexapod_v6:leg_hip", "hexapod_v6:leg_femur", "hexapod_v6:leg_knee",
-- "hexapod_v6:leg_tibia") -- meme principe que "hexapod_v3:leg_joint"
-- (hanche/genou) et "hexapod_v3:leg_part" (femur/tibia), juste avec des
-- noms distincts pour chacune des 4 pieces, comme demande. Pas d'animation
-- de demarche ici (pas demandee) : chaque piece garde une position FIXE
-- (repos), donc pas besoin d'un "hip_pivot" separe comme hexapod_v3 (rien
-- ne tourne independamment du cube entier).
hexapod_v6.leg_femur_height = 2  -- nombre de cubes du femur (horizontal)
hexapod_v6.leg_tibia_height = 3  -- nombre de cubes du tibia (vertical)
hexapod_v6.leg_pair_count = 3    -- 3 paires = 6 pattes

-- Decalage horizontal (X) entre le centre d'un cube (tete ou segment de
-- corps) et le centre de la hanche collee sur son flanc -- les deux ayant
-- la meme demi-largeur (hexapod_v6.size / 2), ce decalage vaut simplement
-- hexapod_v6.size.
hexapod_v6.leg_hip_offset_x = hexapod_v6.size

-- Distance verticale entre le centre d'un cube (tete/corps, hauteur de la
-- hanche) et le point le plus bas des pattes (face inferieure du dernier
-- cube de tibia), utilisee pour poser le hexapod assez haut a la pose pour
-- que ses pattes ne s'enfoncent pas dans le sol (voir le `on_place` de
-- l'item plus bas). Le femur est colle un cran (hexapod_v6.size) sous la
-- hanche ; le premier cube de tibia est a la meme hauteur que le genou (0
-- cran vertical) ; seuls les `leg_tibia_height - 1` cubes de tibia
-- suivants descendent, plus une demi-taille de cube pour atteindre la face
-- basse du dernier.
hexapod_v6.leg_drop = hexapod_v6.size * (hexapod_v6.leg_tibia_height + 0.5)

-- Centres en Z (repere du corps a yaw = 0) des segments qui portent une
-- paire de pattes : le 1er, le 4e et le 7e segment de corps (donc
-- segment_z[2], [5] et [8] -- segment_z[1] etant la tete elle-meme, sans
-- pattes), 2 segments de corps restant donc libres entre deux paires --
-- meme motif que hexapod_v3.leg_pair_spacing (= 3). Avec ce pas de 3
-- segments (9 noeuds) entre deux hanches, et la tibia de chaque patte qui
-- depasse d'un cube entier (hexapod_v6.size) vers l'avant par rapport a sa
-- propre hanche, l'ecart reel entre la tibia d'une patte et la hanche de
-- la suivante est exactement 1 cube (verifie : 9 - size - size = size).
hexapod_v6.leg_z = { hexapod_v6.segment_z[2], hexapod_v6.segment_z[5], hexapod_v6.segment_z[8] }

-- Decalage local {x, y, z} (repere du corps a yaw = 0) de CHAQUE piece de
-- CHAQUE patte, avec le nom d'entite correspondant. Genere en "aplatissant"
-- la chaine hanche -> femur -> genou -> tibia directement en coordonnees
-- relatives au cube entier (pas de parent intermediaire, puisqu'aucune
-- piece ne tourne independamment -- cf. plus haut).
hexapod_v6.leg_piece_offsets = {}
for _, z_center in ipairs(hexapod_v6.leg_z) do
	for _, side in ipairs({ 1, -1 }) do
		local s = hexapod_v6.size  -- taille d'une piece de patte = taille d'un cube tete/corps

		-- Hanche : collee sur le flanc du cube.
		local hip_x = side * hexapod_v6.leg_hip_offset_x
		table.insert(hexapod_v6.leg_piece_offsets,
			{ x = hip_x, y = 0, z = z_center, entity = "hexapod_v6:leg_hip" })

		-- Femur : colle directement sous la hanche, puis continue a
		-- l'horizontale (s'eloigne du cube) a la meme hauteur.
		local femur_x, femur_y = hip_x, -s
		table.insert(hexapod_v6.leg_piece_offsets,
			{ x = femur_x, y = femur_y, z = z_center, entity = "hexapod_v6:leg_femur" })
		for _ = 2, hexapod_v6.leg_femur_height do
			femur_x = femur_x + side * s
			table.insert(hexapod_v6.leg_piece_offsets,
				{ x = femur_x, y = femur_y, z = z_center, entity = "hexapod_v6:leg_femur" })
		end

		-- Genou : au bout du femur.
		local knee_x, knee_y = femur_x + side * s, femur_y
		table.insert(hexapod_v6.leg_piece_offsets,
			{ x = knee_x, y = knee_y, z = z_center, entity = "hexapod_v6:leg_knee" })

		-- Tibia : colle sur la face avant du genou, puis descend a la
		-- verticale (z fixe, y descend).
		local tibia_x, tibia_y, tibia_z = knee_x, knee_y, z_center + s
		table.insert(hexapod_v6.leg_piece_offsets,
			{ x = tibia_x, y = tibia_y, z = tibia_z, entity = "hexapod_v6:leg_tibia" })
		for _ = 2, hexapod_v6.leg_tibia_height do
			tibia_y = tibia_y - s
			table.insert(hexapod_v6.leg_piece_offsets,
				{ x = tibia_x, y = tibia_y, z = tibia_z, entity = "hexapod_v6:leg_tibia" })
		end
	end
end

-- ---------------------------------------------------------------------
-- Liste unifiee de tous les relais de collision (colonnes du corps/tete
-- ET pattes), chacun avec ses PROPRES demi-etendues (les colonnes sont
-- hautes et fines, les pattes sont de petits cubes) : voir
-- hexapod_v6.spawn_colliders, qui cree une entite generique
-- "hexapod_v6:collider" par entree puis lui applique sa propre
-- collisionbox via `set_properties`.
-- ---------------------------------------------------------------------

-- Decalage local {x, z} de CHAQUE colonne de CHAQUE segment (tete +
-- hexapod_v6.body_count segments de corps) : hexapod_v6.column_offsets,
-- decale en Z par hexapod_v6.segment_z pour chaque segment -- 9 * (1 +
-- body_count) relais au total.
hexapod_v6.collider_specs = {}
for _, seg_z in ipairs(hexapod_v6.segment_z) do
	for _, col in ipairs(hexapod_v6.column_offsets) do
		table.insert(hexapod_v6.collider_specs, {
			x = col.x, y = 0, z = col.z + seg_z,
			half_x = hexapod_v6.column_half_horizontal,
			half_y = hexapod_v6.size / 2,
			half_z = hexapod_v6.column_half_horizontal,
		})
	end
end

-- 9 relais par piece de patte (hexapod_v6.leg_piece_offsets), MEME
-- decoupage en colonnes (hexapod_v6.column_offsets) que pour un segment de
-- corps/tete -- necessaire car chaque piece de patte est desormais aussi
-- grande qu'un cube tete/corps (hexapod_v6.size) : une seule boite par
-- piece se heurterait au meme probleme deja rencontre pour le corps (soit
-- elle ne tourne pas avec le yaw, soit -- si elargie pour tenir compte de
-- la rotation -- son coin le plus eloigne depasse la limite de portee du
-- moteur, cf. plus haut). Seul le decalage {x, z} de la colonne est ajoute
-- a celui de la piece ; le decalage vertical (y) reste celui de la piece
-- elle-meme (pas de colonnes superposees ici, une seule suffit sur toute
-- la hauteur de la piece).
for _, piece in ipairs(hexapod_v6.leg_piece_offsets) do
	for _, col in ipairs(hexapod_v6.column_offsets) do
		table.insert(hexapod_v6.collider_specs, {
			x = piece.x + col.x, y = piece.y, z = piece.z + col.z,
			half_x = hexapod_v6.column_half_horizontal,
			half_y = hexapod_v6.size / 2,
			half_z = hexapod_v6.column_half_horizontal,
		})
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

-- Entites de patte ("hexapod_v6:leg_hip" et "hexapod_v6:leg_knee") dont les
-- pieces sont construites avec la texture de jointure plutot que la
-- texture de node -- voir hexapod_v6.spawn_legs.
hexapod_v6.leg_joint_entities = {
	["hexapod_v6:leg_hip"] = true,
	["hexapod_v6:leg_knee"] = true,
}

-- Construit l'assemblage visuel des 6 pattes : pour CHAQUE piece
-- (hexapod_v6.leg_piece_offsets), une grille de 27 blocs (meme principe
-- que hexapod_v6.spawn_blocks) -- chaque piece de patte est ainsi composee
-- de nodes de la taille d'un vrai node de la carte, comme la tete et le
-- corps, plutot qu'un simple cube etire. Hanche et genou utilisent
-- "hexapod_v6:block_joint" (texture de jointure) ; femur et tibia
-- utilisent "hexapod_v6:block" (texture du corps) -- le nom de la piece
-- elle-meme (hanche/femur/genou/tibia) reste identifiable via
-- hexapod_v6.leg_piece_offsets (piece.entity), qui regroupe les 27 blocs
-- de chaque piece.
function hexapod_v6.spawn_legs(self)
	self.legs = {}
	local pod_object = self.object
	local pod_pos = pod_object:get_pos()
	local half_span = (hexapod_v6.blocks_per_side - 1) / 2

	for _, piece in ipairs(hexapod_v6.leg_piece_offsets) do
		local entity_name = hexapod_v6.leg_joint_entities[piece.entity]
			and "hexapod_v6:block_joint" or "hexapod_v6:block"

		for xi = 0, hexapod_v6.blocks_per_side - 1 do
			for yi = 0, hexapod_v6.blocks_per_side - 1 do
				for zi = 0, hexapod_v6.blocks_per_side - 1 do
					local offset = {
						x = piece.x + (xi - half_span) * hexapod_v6.block_size,
						y = piece.y + (yi - half_span) * hexapod_v6.block_size,
						z = piece.z + (zi - half_span) * hexapod_v6.block_size,
					}
					local part = minetest.add_entity(pod_pos, entity_name)
					part:set_attach(pod_object, "",
						{ x = offset.x * 10, y = offset.y * 10, z = offset.z * 10 },
						{ x = 0, y = 0, z = 0 })
					table.insert(self.legs, part)
				end
			end
		end
	end
end

-- Cree les relais de collision (voir hexapod_v6.collider_specs : colonnes
-- du corps/tete + pattes), PAS attaches (`set_attach`) : un objet attache
-- n'a, cote serveur, pas d'autre position que celle de son parent (cf.
-- LuaEntitySAO::step) -- ils sont donc repositionnes chaque pas "a la
-- main" (voir hexapod_v6.reposition_colliders), comme les relais de
-- collision des pattes de hexapod_v3. Chaque relais recoit sa propre
-- collisionbox (`set_properties`), une meme entite generique
-- "hexapod_v6:collider" servant aussi bien aux colonnes (hautes, fines)
-- qu'aux pattes (petits cubes).
function hexapod_v6.spawn_colliders(self)
	self.colliders = {}
	local pod_pos = self.object:get_pos()
	for _, spec in ipairs(hexapod_v6.collider_specs) do
		local collider = minetest.add_entity(vector.add(pod_pos, { x = spec.x, y = spec.y, z = spec.z }),
			"hexapod_v6:collider")
		collider:set_properties({
			collisionbox = {
				-spec.half_x, -spec.half_y, -spec.half_z,
				spec.half_x, spec.half_y, spec.half_z,
			},
		})
		table.insert(self.colliders, collider)
	end
end

-- Repositionne chaque relais de collision (colonne ou patte), en tenant
-- compte de la position ET du yaw courants du cube (le decalage local
-- {x, z} de chaque relais est tourne en consequence). "avant" =
-- minetest.yaw_to_dir(yaw) ; "droite" = son perpendiculaire (verifie a
-- yaw=0 : (1,0,0)). L'axe Y n'a pas besoin d'etre tourne (la rotation se
-- fait uniquement autour de l'axe vertical) : il est applique tel quel,
-- ce qui permet aux relais de pattes (y non nul) de suivre leur propre
-- hauteur.
function hexapod_v6.reposition_colliders(self)
	if not self.colliders then
		return
	end
	local pod_pos = self.object:get_pos()
	local yaw = self.object:get_yaw()
	local forward = minetest.yaw_to_dir(yaw)
	local right = { x = math.cos(yaw), y = 0, z = math.sin(yaw) }
	for i, collider in ipairs(self.colliders) do
		local spec = hexapod_v6.collider_specs[i]
		local world_offset = vector.add(
			vector.multiply(right, spec.x),
			vector.multiply(forward, spec.z))
		world_offset.y = spec.y
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

	minetest.chat_send_player(name, "[Hexapod] Vous descendez du corps.")
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

-- Node individuel des pieces de hanche/genou (voir hexapod_v6.spawn_legs) :
-- identique a "hexapod_v6:block", mais avec la texture de jointure --
-- meme principe que "hexapod_v3:leg_joint" (hanche/genou) distinct de
-- "hexapod_v3:leg_part" (femur/tibia, qui reutilise "hexapod_v6:block").
minetest.register_entity("hexapod_v6:block_joint", {
	initial_properties = {
		visual = "cube",
		visual_size = { x = hexapod_v6.block_size, y = hexapod_v6.block_size, z = hexapod_v6.block_size },
		textures = {
			"hexapod_v6_joint.png", "hexapod_v6_joint.png",
			"hexapod_v6_joint.png", "hexapod_v6_joint.png",
			"hexapod_v6_joint.png", "hexapod_v6_joint.png",
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
	blocks = nil,     -- assemblage visuel du corps/tete (voir hexapod_v6.spawn_blocks)
	legs = nil,       -- assemblage visuel des pattes (voir hexapod_v6.spawn_legs)
	colliders = nil,  -- relais de collision, colonnes + pattes (voir hexapod_v6:collider)

	on_activate = function(self)
		self.object:set_acceleration({ x = 0, y = 0, z = 0 })
		hexapod_v6.pods[self] = true
		hexapod_v6.spawn_blocks(self)
		hexapod_v6.spawn_legs(self)
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
		if self.legs then
			for _, part in ipairs(self.legs) do
				part:remove()
			end
			self.legs = nil
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

		-- +leg_drop remonte le cube de la longueur des pattes, pour que ce
		-- soit leur point le plus bas (et non le dessous du cube tete/corps)
		-- qui touche le ras du sol.
		local pos = vector.add(pointed_thing.above, { x = 0, y = hexapod_v6.leg_drop, z = 0 })
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
