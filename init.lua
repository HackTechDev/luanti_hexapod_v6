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
-- 3 paires de pattes (6 au total, meme forme, position ET demarche animee
-- que hexapod_v3) sont attachees de part et d'autre d'un segment de corps
-- sur deux (voir hexapod_v6.spawn_legs) : chaine hanche -> femur -> genou
-- -> tibia, chaque piece gardant sa propre collision (au repos, non
-- animee -- voir hexapod_v6.leg_piece_offsets).
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
-- Pattes : 3 paires (6 pattes), meme forme, position et demarche que
-- hexapod_v3
-- ---------------------------------------------------------------------
-- Chaine "en L" : corps -> hanche -> femur (horizontal, s'eloigne du
-- corps) -> genou -> tibia (vertical, descend). Chaque piece de patte est
-- de la MEME taille que les cubes de la tete et du corps (hexapod_v6.size,
-- 3x3x3 -- pas la taille d'un simple node), et chaque piece est composee
-- d'un assemblage de 27 blocs ("hexapod_v6:block" pour femur/tibia,
-- "hexapod_v6:block_joint" pour hanche/genou -- voir hexapod_v6.spawn_leg).
--
-- Demarche animee "tripode" (comme un vrai hexapode et comme
-- hexapod_v3.update_legs) : les 6 pattes sont reparties en 2 groupes de 3
-- qui alternent balancement (patte levee, avance) et appui (patte au sol,
-- recule). Pour que la rotation d'une hanche/d'un genou entraine bien tout
-- ce qui est attache en dessous (femur+genou+tibia pour la hanche, tibia
-- pour le genou), chaque piece de patte est un veritable enfant
-- (`set_attach`) de la precedente -- exactement comme hexapod_v3, sauf que
-- chaque "piece" ici est un groupe de 27 blocs attaches a une entite-ancre
-- invisible (`hexapod_v6:leg_anchor`) plutot qu'un unique node visible.
hexapod_v6.leg_femur_height = 2  -- nombre de cubes du femur (horizontal)
hexapod_v6.leg_tibia_height = 3  -- nombre de cubes du tibia (vertical)
hexapod_v6.leg_pair_count = 3    -- 3 paires = 6 pattes

hexapod_v6.leg_hip_swing_deg = 25        -- amplitude du balayage horizontal de la hanche
hexapod_v6.leg_knee_lift_deg = 35        -- amplitude de la levee verticale du genou
hexapod_v6.leg_gait_speed = math.pi * 2  -- vitesse de la phase de marche, en radians/seconde (1 cycle/s par defaut)

-- Son de "pas" joue quand un groupe de pattes (cf. hexapod_v6.update_legs)
-- repose au sol (transition levee -> posee), un seul son par groupe (donc
-- par 3 pattes qui touchent le sol simultanement, plutot qu'un son par
-- patte qui donnerait 3 copies superposees).
hexapod_v6.footstep_sound = "hexapod_v6_footstep"
hexapod_v6.footstep_sound_gain = 0.5
hexapod_v6.footstep_sound_max_hear_distance = 16

-- Son de "moteur" joue en boucle tant que le hexapod avance (touche Haut),
-- comme hexapod_v3.engine_sound.
hexapod_v6.engine_sound = "hexapod_v6_engine"
hexapod_v6.engine_sound_gain = 0.5
hexapod_v6.engine_sound_max_hear_distance = 16

-- Son de "direction" joue en boucle tant que le hexapod pivote
-- (Gauche/Droite), comme hexapod_v3.turn_sound.
hexapod_v6.turn_sound = "hexapod_v6_turn"
hexapod_v6.turn_sound_gain = 0.4
hexapod_v6.turn_sound_max_hear_distance = 16

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
-- CHAQUE patte AU REPOS (position neutre, sans balancement/levee), avec un
-- nom indicatif. Genere en "aplatissant" la chaine hanche -> femur -> genou
-- -> tibia directement en coordonnees relatives au cube entier.
--
-- Utilise UNIQUEMENT pour la collision (hexapod_v6.collider_specs
-- ci-dessous) : comme hexapod_v3, la collision des pattes reste au repos
-- et ne suit PAS l'animation de la demarche (hexapod_v6.update_legs) --
-- seule la partie VISIBLE des pattes est animee (voir hexapod_v6.spawn_leg,
-- qui construit une chaine hierarchique separee, animee celle-la).
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

-- Attache une entite-ancre invisible ("hexapod_v6:leg_anchor") a
-- `parent_object`, avec un decalage local `offset` ({x,y,z}, en noeuds) et
-- une rotation optionnelle. Sert soit de support a un groupe de 27 blocs
-- (une "piece" de patte, voir hexapod_v6.spawn_leg_piece), soit de pivot
-- pur sans bloc attache (le "hip_pivot" de hexapod_v6.spawn_leg).
function hexapod_v6.spawn_leg_anchor(self, parent_object, parent_pos, offset, rotation)
	local anchor = minetest.add_entity(parent_pos, "hexapod_v6:leg_anchor")
	anchor:set_attach(parent_object, "",
		{ x = offset.x * 10, y = offset.y * 10, z = offset.z * 10 },
		rotation or { x = 0, y = 0, z = 0 })
	table.insert(self.leg_anchors, anchor)
	return anchor
end

-- Construit une "piece" de patte (hanche, un segment de femur, genou, ou
-- un segment de tibia) : une entite-ancre (voir hexapod_v6.spawn_leg_anchor)
-- attachee a `parent_object` avec le decalage `offset`, portant une grille
-- de 27 blocs (`entity_name`, meme principe que hexapod_v6.spawn_blocks) --
-- chaque piece de patte est ainsi composee de nodes de la taille d'un vrai
-- node de la carte, comme la tete et le corps, plutot qu'un simple cube
-- etire. Retourne l'ancre, pour que l'appelant puisse y attacher la piece
-- suivante de la chaine.
function hexapod_v6.spawn_leg_piece(self, entity_name, parent_object, parent_pos, offset)
	local anchor = hexapod_v6.spawn_leg_anchor(self, parent_object, parent_pos, offset)
	local half_span = (hexapod_v6.blocks_per_side - 1) / 2

	for xi = 0, hexapod_v6.blocks_per_side - 1 do
		for yi = 0, hexapod_v6.blocks_per_side - 1 do
			for zi = 0, hexapod_v6.blocks_per_side - 1 do
				local block_offset = {
					x = (xi - half_span) * hexapod_v6.block_size,
					y = (yi - half_span) * hexapod_v6.block_size,
					z = (zi - half_span) * hexapod_v6.block_size,
				}
				local block = minetest.add_entity(parent_pos, entity_name)
				block:set_attach(anchor, "",
					{ x = block_offset.x * 10, y = block_offset.y * 10, z = block_offset.z * 10 },
					{ x = 0, y = 0, z = 0 })
				table.insert(self.leg_blocks, block)
			end
		end
	end

	return anchor
end

-- Construit une patte complete "en L" (hanche -> femur horizontal -> genou
-- -> tibia vertical), suspendue sous le flanc (`side` = 1 pour droite, -1
-- pour gauche) du cube situe a `z_center`, et assignee au groupe de
-- demarche `group` (1 ou 2, cf. hexapod_v6.update_legs) -- meme
-- construction chainee que hexapod_v3.spawn_leg (chaque piece est un
-- veritable enfant de la precedente, pour qu'une rotation entraine tout ce
-- qui est attache en dessous), sauf que chaque "piece" ici est un groupe
-- de 27 blocs (hexapod_v6.spawn_leg_piece) plutot qu'un unique node.
--
-- La hanche elle-meme NE DOIT PAS bouger : le pivot qui l'anime (rotation
-- Y = balayage avant/arriere de toute la patte) est un "hip_pivot" separe,
-- colle exactement dessus (decalage nul). Le genou, lui, sert directement
-- de pivot pour le tibia (rotation X = levee/pose du pied) : inutile
-- d'avoir un pivot separe pour lui, contrairement a la hanche, puisque
-- rien d'autre que le tibia ne depend de sa position au repos.
function hexapod_v6.spawn_leg(self, pod_object, pod_pos, z_center, side, group)
	local s = hexapod_v6.size

	local hip_x = side * hexapod_v6.leg_hip_offset_x
	local hanche = hexapod_v6.spawn_leg_piece(self, "hexapod_v6:block_joint", pod_object, pod_pos,
		{ x = hip_x, y = 0, z = z_center })

	-- Pivot de hanche : colle exactement sur la hanche (decalage nul),
	-- immobile au repos ; seule sa rotation sera animee.
	local hip_pivot = hexapod_v6.spawn_leg_anchor(self, hanche, pod_pos, { x = 0, y = 0, z = 0 })

	-- Premier node de femur : colle directement sous le pivot de hanche.
	local first_femur = hexapod_v6.spawn_leg_piece(self, "hexapod_v6:block", hip_pivot, pod_pos,
		{ x = 0, y = -s, z = 0 })

	-- Nodes de femur suivants : a l'horizontale, chaines les uns aux
	-- autres, a la meme hauteur.
	local femur_end = first_femur
	for _ = 2, hexapod_v6.leg_femur_height do
		femur_end = hexapod_v6.spawn_leg_piece(self, "hexapod_v6:block", femur_end, pod_pos,
			{ x = side * s, y = 0, z = 0 })
	end

	local genou_offset = { x = side * s, y = 0, z = 0 }
	local genou = hexapod_v6.spawn_leg_piece(self, "hexapod_v6:block_joint", femur_end, pod_pos, genou_offset)

	-- Premier node de tibia : colle sur la face avant du genou.
	local first_tibia = hexapod_v6.spawn_leg_piece(self, "hexapod_v6:block", genou, pod_pos,
		{ x = 0, y = 0, z = s })

	-- Nodes de tibia suivants : a la verticale, chaines les uns aux
	-- autres, sous le premier.
	local tibia_end = first_tibia
	for _ = 2, hexapod_v6.leg_tibia_height do
		tibia_end = hexapod_v6.spawn_leg_piece(self, "hexapod_v6:block", tibia_end, pod_pos,
			{ x = 0, y = -s, z = 0 })
	end

	table.insert(self.leg_pivots, {
		hip_pivot = hip_pivot,
		hip_pivot_parent = hanche,
		genou = genou,
		genou_parent = femur_end,
		genou_offset = genou_offset,
		group = group,
	})
end

-- Construit les 3 paires de pattes (hexapod_v6.leg_z), une paire par
-- element de cette liste, en alternant le groupe de demarche paire par
-- paire et cote par cote (cf. hexapod_v6.spawn_leg) -- meme motif que
-- hexapod_v3.spawn_legs : deux pattes voisines (meme paire, ou meme cote
-- sur deux paires consecutives) ne sont jamais dans le meme groupe.
function hexapod_v6.spawn_legs(self)
	self.leg_blocks = {}
	self.leg_anchors = {}
	self.leg_pivots = {}
	local pod_object = self.object
	local pod_pos = pod_object:get_pos()

	for i, z_center in ipairs(hexapod_v6.leg_z) do
		hexapod_v6.spawn_leg(self, pod_object, pod_pos, z_center, 1, (i % 2 == 0) and 1 or 2)   -- droite
		hexapod_v6.spawn_leg(self, pod_object, pod_pos, z_center, -1, (i % 2 == 0) and 2 or 1)  -- gauche
	end
end

-- Anime la demarche "tripode" des pattes : les deux groupes (1 et 2, cf.
-- hexapod_v6.spawn_legs) sont en opposition de phase (dephasage de pi), de
-- sorte que lorsque l'un est en balancement (patte levee, avance),
-- l'autre est en appui (patte au sol, recule), et inversement -- exactement
-- comme hexapod_v3.update_legs.
--
-- Le pivot de hanche et le genou etant attaches (`set_rotation()` est
-- ignore sur un objet attache, cf. lua_api.md), on reanime leur rotation
-- en rappelant `set_attach` a chaque pas avec le meme decalage de position
-- mais une nouvelle rotation :
-- - pivot de hanche (decalage nul, colle sur la hanche) : rotation.y
--   (horizontale) = balayage avant/arriere de toute la patte
--   (femur+genou+tibia, qui lui sont tous attaches en cascade), la hanche
--   elle-meme restant immobile ;
-- - genou : rotation.x (verticale) = levee/pose du tibia seul. La levee
--   n'a lieu que sur la moitie "avant" du cycle (sin > 0, phase de
--   balancement) ; le genou reste a plat (0) pendant la moitie "arriere"
--   (phase d'appui), pour que la patte pousse au sol sans se relever.
--
-- IMPORTANT : la collision des pattes (hexapod_v6.collider_specs), elle,
-- reste au repos et ne suit PAS cette animation -- exactement comme
-- hexapod_v3 (voir hexapod_v6.leg_piece_offsets).
--
-- Son de pas : joue hexapod_v6.footstep_sound des qu'un groupe (1 ou 2)
-- passe de "leve" (sin(phase) > 0, comme pour knee_deg ci-dessous) a
-- "pose" -- un seul appel par GROUPE (donc par 3 pattes qui se posent
-- ensemble), pas par patte individuelle, pour eviter 3 sons superposes au
-- meme instant.
function hexapod_v6.update_legs(self, dtime, moving)
	if not self.leg_pivots then
		return
	end

	if moving then
		self.leg_phase = (self.leg_phase + hexapod_v6.leg_gait_speed * dtime) % (2 * math.pi)
	end

	for group = 1, 2 do
		local group_phase = self.leg_phase + (group == 1 and 0 or math.pi)
		local lifted = math.sin(group_phase) > 0
		if self.leg_group_lifted[group] and not lifted then
			minetest.sound_play(hexapod_v6.footstep_sound, {
				object = self.object,
				gain = hexapod_v6.footstep_sound_gain,
				max_hear_distance = hexapod_v6.footstep_sound_max_hear_distance,
			})
		end
		self.leg_group_lifted[group] = lifted
	end

	for _, leg in ipairs(self.leg_pivots) do
		local phase = self.leg_phase + (leg.group == 1 and 0 or math.pi)
		local hip_deg = hexapod_v6.leg_hip_swing_deg * math.sin(phase)
		local knee_deg = hexapod_v6.leg_knee_lift_deg * math.max(0, math.sin(phase))

		leg.hip_pivot:set_attach(leg.hip_pivot_parent, "",
			{ x = 0, y = 0, z = 0 },
			{ x = 0, y = hip_deg, z = 0 })
		leg.genou:set_attach(leg.genou_parent, "",
			{ x = leg.genou_offset.x * 10, y = leg.genou_offset.y * 10, z = leg.genou_offset.z * 10 },
			{ x = knee_deg, y = 0, z = 0 })
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
--
-- IMPORTANT : `selectionbox` est repassee explicitement a zero dans ce
-- MEME appel a `set_properties`. Sans elle, le moteur la recalcule par
-- defaut a partir de la NOUVELLE `collisionbox` (celle du relais, pas
-- nulle) des que `set_properties` est appele -- ce qui annule la
-- `selectionbox` nulle declaree dans `initial_properties` et rend chaque
-- relais a nouveau cliquable (verifie en jeu : les clics droits pres du
-- cube visaient les relais au lieu de "hexapod_v6:pod", empechant de
-- piloter le hexapod en cliquant sur la tete).
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
			selectionbox = { 0, 0, 0, 0, 0, 0 },
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

-- Demarre/arrete un son en boucle attache au hexapod selon une condition
-- booleenne (`active`), en se souvenant de son handle dans le champ
-- `self[handle_field]` pour pouvoir l'arreter plus tard -- meme fonction
-- que hexapod_v3.set_looping_sound. Le son est positionne sur l'entite
-- (`object = self.object`) : le moteur audio du client le repositionne
-- lui-meme a chaque image tant qu'il joue, pas besoin de le relancer pour
-- le faire suivre le hexapod.
function hexapod_v6.set_looping_sound(self, handle_field, active, sound_name, gain, max_hear_distance)
	if active and not self[handle_field] then
		self[handle_field] = minetest.sound_play(sound_name, {
			object = self.object,
			gain = gain,
			max_hear_distance = max_hear_distance,
			loop = true,
		})
	elseif not active and self[handle_field] then
		minetest.sound_stop(self[handle_field])
		self[handle_field] = nil
	end
end

-- Joue le son de moteur tant que le hexapod avance (signed_speed
-- strictement positif), et l'arrete des qu'il ne va plus vers l'avant
-- (arret, marche arriere ou pivot sur place) -- comme
-- hexapod_v3.update_engine_sound.
function hexapod_v6.update_engine_sound(self, signed_speed)
	hexapod_v6.set_looping_sound(self, "engine_sound_handle", signed_speed > 0,
		hexapod_v6.engine_sound, hexapod_v6.engine_sound_gain,
		hexapod_v6.engine_sound_max_hear_distance)
end

-- Joue le son de direction tant que le hexapod pivote (Gauche ou Droite),
-- que ce soit sur place ou en avancant/reculant en meme temps -- comme
-- hexapod_v3.update_turn_sound.
function hexapod_v6.update_turn_sound(self, turning)
	hexapod_v6.set_looping_sound(self, "turn_sound_handle", turning,
		hexapod_v6.turn_sound, hexapod_v6.turn_sound_gain,
		hexapod_v6.turn_sound_max_hear_distance)
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

-- Ancre invisible d'une piece de patte (voir hexapod_v6.spawn_leg_piece et
-- hexapod_v6.spawn_leg_anchor) : porte soit les 27 blocs d'une piece
-- (hanche, un segment de femur, genou, ou un segment de tibia), soit rien
-- du tout quand elle sert de pivot pur (le "hip_pivot" de
-- hexapod_v6.spawn_leg). Sa rotation est reanimee chaque pas pour la
-- hanche et le genou (hexapod_v6.update_legs) -- exactement comme
-- "hexapod_v3:leg_pivot".
--
-- IMPORTANT : `visual_size` ne doit PAS etre nul ({0,0,0}). Les 27 blocs
-- d'une piece (et, pour le pivot de hanche, tout le reste de la patte) sont
-- de veritables enfants (`set_attach`) de cette entite : une echelle nulle
-- sur le parent se propage multiplicativement a tous ses descendants dans
-- le graphe de scene, ce qui les rendrait tous invisibles quelle que soit
-- leur propre `visual_size` (meme mecanisme que "hexapod_v6:pod" et
-- "hexapod_v3:leg_pivot"). On utilise donc une echelle neutre ({1,1,1}) et
-- une texture reellement transparente pour la rendre invisible sans
-- toucher a son echelle.
minetest.register_entity("hexapod_v6:leg_anchor", {
	initial_properties = {
		visual = "cube",
		visual_size = { x = 1, y = 1, z = 1 },
		textures = {
			"hexapod_v6_invisible.png", "hexapod_v6_invisible.png",
			"hexapod_v6_invisible.png", "hexapod_v6_invisible.png",
			"hexapod_v6_invisible.png", "hexapod_v6_invisible.png",
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
	blocks = nil,       -- assemblage visuel du corps/tete (voir hexapod_v6.spawn_blocks)
	leg_blocks = nil,   -- les 27 blocs de chaque piece de patte (voir hexapod_v6.spawn_leg_piece)
	leg_anchors = nil,  -- ancres invisibles des pieces de patte, y compris les pivots (voir hexapod_v6.spawn_leg)
	leg_pivots = nil,   -- pivots (hanche/genou) de chaque patte, pour la demarche (voir hexapod_v6.update_legs)
	leg_phase = 0,
	leg_group_lifted = nil,  -- etat leve/pose de chaque groupe (1 et 2), pour le son de pas (voir hexapod_v6.update_legs)
	colliders = nil,    -- relais de collision, colonnes + pattes (voir hexapod_v6:collider)
	engine_sound_handle = nil,
	turn_sound_handle = nil,

	on_activate = function(self)
		self.object:set_acceleration({ x = 0, y = 0, z = 0 })
		hexapod_v6.pods[self] = true
		self.leg_group_lifted = { false, false }
		hexapod_v6.spawn_blocks(self)
		hexapod_v6.spawn_legs(self)
		hexapod_v6.spawn_colliders(self)
	end,

	on_deactivate = function(self)
		if self.driver and self.driver:is_player() then
			hexapod_v6.stop_driving(self, self.driver)
		end
		if self.engine_sound_handle then
			minetest.sound_stop(self.engine_sound_handle)
			self.engine_sound_handle = nil
		end
		if self.turn_sound_handle then
			minetest.sound_stop(self.turn_sound_handle)
			self.turn_sound_handle = nil
		end
		if self.blocks then
			for _, block in ipairs(self.blocks) do
				block:remove()
			end
			self.blocks = nil
		end
		if self.leg_blocks then
			for _, block in ipairs(self.leg_blocks) do
				block:remove()
			end
			self.leg_blocks = nil
		end
		if self.leg_anchors then
			for _, anchor in ipairs(self.leg_anchors) do
				anchor:remove()
			end
			self.leg_anchors = nil
		end
		self.leg_pivots = nil
		self.leg_group_lifted = nil
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
		local turning = false
		local moving = false
		local signed_speed = 0

		if driver and driver:is_player() then
			local ctrl = driver:get_player_control()
			local yaw = self.object:get_yaw()

			if ctrl.left then
				yaw = yaw + hexapod_v6.turn_speed * dtime
				turning = true
			end
			if ctrl.right then
				yaw = yaw - hexapod_v6.turn_speed * dtime
				turning = true
			end
			self.object:set_yaw(yaw)

			local dir = minetest.yaw_to_dir(yaw)
			local vel = { x = 0, y = 0, z = 0 }
			if ctrl.up then
				vel = vector.multiply(dir, hexapod_v6.forward_speed)
				moving = true
				signed_speed = hexapod_v6.forward_speed
			elseif ctrl.down then
				vel = vector.multiply(dir, -hexapod_v6.forward_speed)
				moving = true
				signed_speed = -hexapod_v6.forward_speed
			end
			self.object:set_velocity(vel)

			hexapod_v6.update_camera(self, driver)
		else
			self.driver = nil
		end

		hexapod_v6.reposition_colliders(self)
		hexapod_v6.update_legs(self, dtime, moving or turning)
		hexapod_v6.update_engine_sound(self, signed_speed)
		hexapod_v6.update_turn_sound(self, turning)
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
