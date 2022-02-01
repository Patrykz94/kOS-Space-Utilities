// Rodrigues vector rotation formula - Borrowed from PEGAS
FUNCTION Rodrigues {
	PARAMETER inVector. //  Expects a vector
	PARAMETER axis.   //  Expects a vector
	PARAMETER angle.  //  Expects a scalar

	SET axis TO axis:NORMALIZED.

	LOCAL outVector IS inVector*COS(angle).
	SET outVector TO outVector + VCRS(axis, inVector)*SIN(angle).
	SET outVector TO outVector + axis*VDOT(axis, inVector)*(1-COS(angle)).

	RETURN outVector.
}

// Function that returns a normal vector
FUNCTION GetNormalVec {
	PARAMETER prog IS SHIP:VELOCITY:SURFACE, pos IS SHIP:POSITION - BODY:POSITION.
	RETURN VCRS(prog,pos).
}

// nodeFromVector - originally created by reddit user ElWanderer_KSP
FUNCTION NodeFromVector {
	PARAMETER vec, n_time IS TIME:SECONDS.

	LOCAL s_pro IS VELOCITYAT(SHIP,n_time):SURFACE.
	LOCAL s_pos IS POSITIONAT(SHIP,n_time) - BODY:POSITION.
	LOCAL s_nrm IS VCRS(s_pro,s_pos).
	LOCAL s_rad IS VCRS(s_nrm,s_pro).

	RETURN NODE(n_time, VDOT(vec,s_rad:NORMALIZED), VDOT(vec,s_nrm:NORMALIZED), VDOT(vec,s_pro:NORMALIZED)).
}