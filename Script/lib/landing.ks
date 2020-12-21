// A landing library that requires Trajectories Mod.
@LAZYGLOBAL OFF.

// A function that does a simple landing on a non atmospheric body.
FUNCTION Land_Anywhere {
	IF ADDONS:TR:AVAILIABLE {
		LOCAL impactTime IS 0.
		UNTIL FALSE {
			IF ADDONS:TR:HASIMPACT { SET impactTime TO ADDONS:TR:TIMETILLIMPACT. }
		}
	} ELSE {
		RETURN FALSE.
	}
}