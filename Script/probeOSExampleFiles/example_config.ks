LOCAL command_faceSun IS {
	LOCAL rot IS vehicle["control-type"]["rotation"].
	IF NOT steeringLocked {
		IF rot = "rcs" {
			RCS ON.
		}
		LOCK STEERING TO vehicle["standby-facing"]["facing-vector"].
		SET steeringLocked TO TRUE.
		WAIT UNTIL (VANG(SHIP:FACING:VECTOR, vehicle["standby-facing"]["facing-vector"]) < 0.1) AND (SHIP:ANGULARVEL:MAG < 0.001).
		WAIT 5.
		UNLOCK STEERING.
		SET steeringLocked TO FALSE.
		RCS OFF.
		SAS ON.
		WAIT 0.
		KUNIVERSE:TIMEWARP:WARPTO(TIME:SECONDS + 1).
		Notify("Facing the sun! Remember to set rotation relative to Sun in Persistant Rotation", 10, GREEN).
	}
}.

SET vehicle TO LEXICON(
	"standby-facing", LEXICON(
		"facing-vector", SUN:POSITION,
		"face", command_faceSun@
	),
	"control-type", LEXICON(
		"rotation", "reactionWheel",
		"translation", "rcs"
	)
).