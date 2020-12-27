// A landing library - Using Trajectories
@LAZYGLOBAL OFF.

// A function that does a simple landing on a non atmospheric body.
FUNCTION Land_Anywhere {
	IF ADDONS:TR:AVAILABLE {
		// Complete a de-orbit burn first that makes the lander impact in less that 10 minutes from now

		LOCK STEERING TO LOOKDIRUP(-SHIP:VELOCITY:ORBIT, SHIP:FACING:TOPVECTOR).
		WAIT UNTIL VANG(-SHIP:VELOCITY:ORBIT, SHIP:FACING:FOREVECTOR) < 0.1.
		IF NOT ADDONS:TR:HASIMPACT OR ADDONS:TR:TIMETILLIMPACT > 900 {
			IF SHIP:MAXTHRUSTAT(0) = 0 { STAGE. }
			LOCK THROTTLE TO 1.
			WAIT UNTIL ADDONS:TR:HASIMPACT AND ADDONS:TR:TIMETILLIMPACT < 900.
			LOCK THROTTLE TO 0.
		}

		LOCAL allEngines IS LIST().
		LIST ENGINES IN allEngines.
		LOCAL landingEngines IS LIST().
		FOR eng IN allEngines {
			IF eng:IGNITION AND NOT eng:FLAMEOUT { landingEngines:ADD(eng). }
		}
		LOCAL landingLex IS Land_CalculateLandingBurn(landingEngines, 388, 0, 5).
		IF landingLex["TrajectoryFound"] {
			LOCK STEERING TO LOOKDIRUP(Rodrigues(-SHIP:VELOCITY:SURFACE, VCRS(SHIP:VELOCITY:SURFACE, BODY:POSITION), landingLex["Angle"]):NORMALIZED, SHIP:FACING:TOPVECTOR).
			LOCAL burnAlarm IS ADDALARM("Raw", landingLex["StartTime"] - 15, "Landing Burn Alarm", SHIP:NAME + " has a scheduled landing burn in 15 seconds. Time to point retrograde.").
			SET burnAlarm:ACTION TO "KillWarpOnly".
			HUDTEXT("kOS: Timewarp can be used.", 10, 2, 20, GREEN, FALSE).
			UNTIL landingLex["StartTime"] <= TIME:SECONDS {
				PRINT "BURN ETA: " + ROUND(landingLex["StartTime"] - TIME:SECONDS) + "    " AT (1,29).
			}
			LOCK THROTTLE TO 1.
			WAIT UNTIL SHIP:VELOCITY:SURFACE:MAG < 25 OR ALT:RADAR < 500 OR SHIP:MAXTHRUSTAT(0) = 0.
			LOCK THROTTLE TO 0.
			UNLOCK ALL.
			WAIT 0.
			STAGE.
			Land_Touchdown().
		}
	} ELSE {
		PRINT "Trajectories Mod not available!".
		RETURN FALSE.
	}
}

FUNCTION Land_Touchdown {
	LOCAL vSpeed IS 0.
	LOCAL landAlt IS 0.
	LOCAL tval IS 0.
	LOCK THROTTLE TO tval.
	LOCK STEERING TO LOOKDIRUP(-SHIP:VELOCITY:SURFACE, SHIP:FACING:TOPVECTOR).
	LOCAL VelThr_PID IS PIDLOOP(6, 0, 1, 0.005, 1).

	LOCAL boundsBox IS SHIP:BOUNDS.
	LOCAL curAlt IS ALT:RADAR.

	LOCAL originalIPU TO CONFIG:IPU.
	SET CONFIG:IPU TO 2000.

	LOCAL TWR IS SHIP:MAXTHRUSTAT(0)/SHIP:MASS/Gravity(SHIP:ALTITUDE).

	WHEN ALT:RADAR < 50 THEN { GEAR ON. }
	WHEN ALT:RADAR < 50 AND SHIP:VELOCITY:SURFACE:MAG < 2 THEN { LOCK STEERING TO LOOKDIRUP(-BODY:POSITION, SHIP:FACING:TOPVECTOR). }

	CLEARSCREEN.

	UNTIL STATUS = "LANDED" OR VERTICALSPEED > 0 {
		SET curAlt TO CHOOSE ALT:RADAR IF ALT:RADAR > 50 ELSE boundsBox:BOTTOMALTRADAR.
		SET vSpeed TO MAX(MIN(((1/MAX(0.1, (curAlt - landAlt))^(0.5-((TWR-1)/6)) * ((curAlt - landAlt) * 0.50))* -1), -0.1), -25).
		SET VelThr_PID:SETPOINT TO vSpeed.

		PRINT "LANDING BURN - TOUCHDOWN PART" AT (1,1).

		PRINT "Current Altitude:      " + ROUND(curAlt - landAlt,2) + "m     " AT (1,3).
		PRINT "Desired Descent Speed: " + ROUND(vSpeed,2) + "m/s     " AT (1,4).
		PRINT "Current Descent Speed: " + ROUND(VERTICALSPEED,2) + "m/s     " AT (1,5).
		SET tval TO VelThr_PID:UPDATE(TIME:SECONDS, VERTICALSPEED).
	}

	LOCK THROTTLE TO 0.
	UNLOCK ALL.

	SET CONFIG:IPU TO originalIPU.
}

// Takes geoposition and time
// Returns original geoposition adjusted by how much the planet will have rotated by the specified time
FUNCTION Land_GetFutureGeoposition {
	PARAMETER posCoordinates, futureTime.

	LOCAL longitudeOffset IS (futureTime - TIME:SECONDS) / BODY:ROTATIONPERIOD * 360.

	RETURN LATLNG(posCoordinates:LAT, MOD(posCoordinates:LNG + longitudeOffset, 360)).
}

FUNCTION Land_CalculateLandingBurn {
	PARAMETER engs, dryMass, angle IS 0, timeStep IS 1, endAlt IS 500, endSpeed IS 25.

	CLEARSCREEN.

	LOCAL beginning IS TIME:SECONDS.

	LOCAL originalIPU TO CONFIG:IPU.
	SET CONFIG:IPU TO 2000.

	LOCAL impactTime IS TIME:SECONDS + ADDONS:TR:TIMETILLIMPACT.
	LOCAL startMass IS SHIP:MASS * 1000.

	LOCAL engThrust IS 0.
	LOCAL engISP IS 0.
	LOCAL engNum IS engs:LENGTH.
	LOCAL massFlow IS 0.

	FOR eng IN engs {
		SET engThrust TO engThrust + eng:POSSIBLETHRUSTAT(0) * 1000.
		SET massFlow TO massFlow + eng:POSSIBLETHRUSTAT(0) * 1000 / (eng:VISP * CONSTANT:g0).
		SET engISP TO engISP + eng:VISP.
	}

	SET engISP TO engISP/engNum.

	LOCAL startTime IS TIME:SECONDS + 30.
	LOCAL simCycles IS 0.
	LOCAL returnLex IS LEXICON().

	UNTIL FALSE {

		LOCAL newTim IS startTime.
		LOCAL newVel IS VELOCITYAT(SHIP, newTim):SURFACE.
		LOCAL newPos IS -BODY:POSITION + POSITIONAT(SHIP, newTim).
		LOCAL newAlt IS BODY:ALTITUDEOF(newPos).
		LOCAL newHei IS Land_GetGeopositionAt(newTim, BODY:GEOPOSITIONOF(newPos)):TERRAINHEIGHT.
		LOCAL newMas IS startMass.
		LOCAL newAcc IS v(0,0,0).
		LOCAL newGra IS (BODY:POSITION - newPos):NORMALIZED * Gravity(newAlt).

		PRINT "INITIAL VALUES" AT(1,1).
		PRINT "ETA:         " + ROUND(newTim - TIME:SECONDS, 2) + "       " AT(1,3).
		PRINT "Speed:       " + ROUND(newVel:MAG, 2) + "       " AT(1,4).
		PRINT "Altitude:    " + ROUND(newAlt, 2) + "       " AT(1,5).
		PRINT "Height:      " + ROUND(newHei, 2) + "       " AT(1,6).
		PRINT "Fuel Left:   " + ROUND(newMas - dryMass, 2) + "       " AT(1,7).
		PRINT "DeltaV Used: " + ROUND(engISP * CONSTANT:g0 * LN(startMass / newMas), 2) + "       " AT(1,8).
		PRINT "SIMULATION STARTED" AT(1,10).

		//LOCAL vec IS VECDRAW(SHIP:POSITION, {RETURN newGra * 10.}, RED, "Gravity", 1, TRUE, 0.2, TRUE).
		//LOCAL vec2 IS VECDRAW(SHIP:POSITION, {RETURN newVel / 100.}, BLUE, "Velocity", 1, TRUE, 0.2, TRUE).

		LOCAL oldTim IS newTim.
		LOCAL oldVel IS newVel.
		LOCAL oldPos IS newPos.
		LOCAL oldAlt IS newAlt.
		LOCAL oldHei IS newHei.
		LOCAL oldMas IS newMas.
		LOCAL oldAcc IS newAcc.
		LOCAL oldGra IS newGra.

		LOCAL cycleStartTime IS TIME:SECONDS.

		FUNCTION printResults {
			PRINT "ETA:         " + ROUND(newTim - TIME:SECONDS, 2) + "    " + ROUND(newTim-startTime, 2) + "       " AT(1,12).
			PRINT "Speed:       " + ROUND(newVel:MAG, 2) + "       " AT(1,13).
			PRINT "Altitude:    " + ROUND(newAlt, 2) + "       " AT(1,14).
			PRINT "Height:      " + ROUND(newHei, 2) + "       " AT(1,15).
			PRINT "Fuel Left:   " + ROUND(newMas - dryMass, 2) + "       " AT(1,16).
			PRINT "DeltaV Used: " + ROUND(engISP * CONSTANT:g0 * LN(startMass / newMas), 2) + "       " AT(1,17).
			PRINT "Time:        " + ROUND(TIME:SECONDS - cycleStartTime, 3) + "       " AT(1,18).
			PRINT "Angle Used:  " + angle + "       " AT(1,19).
		}

		UNTIL FALSE {
			// update old vars
			SET oldTim TO newTim.
			SET oldVel TO newVel.
			SET oldPos TO newPos.
			SET oldAlt TO newAlt.
			SET oldHei TO newHei.
			SET oldMas TO newMas.
			SET oldAcc TO newAcc.
			SET oldGra TO newGra.

			// update new vars
			SET newTim TO newTim + timeStep.
			SET newVel TO newVel + (newAcc * timeStep) + (newGra * timeStep).
			SET newPos TO newPos + (newVel * timeStep).// + BODY:POSITION.
			SET newAlt TO BODY:ALTITUDEOF(newPos + BODY:POSITION).
			SET newHei TO Land_GetGeopositionAt(newTim, BODY:GEOPOSITIONOF(newPos)):TERRAINHEIGHT.
			SET newMas TO newMas - (massFlow * timeStep).
			SET newAcc TO Rodrigues(-newVel, VCRS(newVel, -newPos), angle):NORMALIZED * engThrust / newMas.
			SET newGra TO (-newPos):NORMALIZED * Gravity(newAlt).

			IF 1=2 AND timeStep > 0.1 AND (newVel:MAG < endSpeed OR newAlt - newHei < endAlt) {
				PRINT "Changed to 0.1" AT (1, 25).
				SET timeStep TO 0.1.
				SET newTim TO oldTim.
				SET newVel TO oldVel.
				SET newPos TO oldPos.
				SET newAlt TO oldAlt.
				SET newHei TO oldHei.
				SET newMas TO oldMas.
				SET newAcc TO oldAcc.
				SET newGra TO oldGra.
			} ELSE {
				IF newAlt - newHei < endAlt { printResults(). BREAK. }
				IF newAlt < newHei { printResults(). BREAK. }
				IF newVel:MAG < endSpeed { printResults(). BREAK. }
				IF newMas < dryMass { printResults(). BREAK. }
			}
		}

		SET simCycles TO simCycles + 1.
		PRINT "SIMULATION ENDED. Cycles Completed: " + simCycles + "       " AT(1,21).

		IF newAlt - newHei > endAlt - 50 AND newAlt - newHei < endAlt
		AND newVel:MAG <= endSpeed AND newMas >= dryMass {
			PRINT "Landing Trajectory calculated:" AT(1,23).
			PRINT "Start Time:      " + ROUND (startTime) + "  ETA: " + ROUND(startTime - TIME:SECONDS) AT(1,24).
			PRINT "Descent Angle:   " + angle AT(1,25).
			PRINT "DeltaV Used:     " + ROUND(engISP * CONSTANT:g0 * LN(startMass / newMas), 2) AT(1,26).
			PRINT "Cycles Complete: " + simCycles AT(1,27).
			returnLex:ADD("TrajectoryFound", TRUE).
			returnLex:ADD("StartTime", startTime).
			returnLex:ADD("Angle", angle).
			BREAK.
		} ELSE IF newMas < dryMass {
			IF angle < 10 { SET angle TO angle + 1. }
			ELSE { BREAK. }
		} ELSE IF newAlt - newHei < endAlt AND newVel:MAG > endSpeed {
			IF startTime < beginning + 30 {
				IF angle < 10 { SET angle TO angle + 1. }
			} ELSE {
				SET startTime TO startTime - 1.
			}
		} ELSE IF newAlt - newHei >= endAlt AND newVel:MAG < endSpeed {
			IF newAlt - newHei - endAlt > 500 {
				SET startTime TO startTime + 10.
			} ELSE IF newAlt - newHei - endAlt > 100 {
				SET startTime TO startTime + 5.
			} ELSE {
				SET timeStep TO 1.
				SET startTime TO startTime + 1.
			}
		}
	}
	SET CONFIG:IPU TO originalIPU.
	IF NOT returnLex:HASSUFFIX("TrajectoryFound") { returnLex:ADD("TrajectoryFound", FALSE). }
	RETURN returnLex.
}

// A forward simulation that calculates the landing burn start time and burn vector
// to bring the landing location as close to the target as possible. Assumes constant thrust
FUNCTION Land_ForwardSim {
	PARAMETER landingEngines, landerDryMass, desiredLocation IS "unspecified", desiredAltitude IS 500, desiredSpeed IS 25, initialTimeStep IS 5.

	// Create the return lexicon with default values
	LOCAL landingLex IS LEXICON("calculated", FALSE, "startTime", 0, "vAngle", 0, "hAngle", 0).

	// Declare engine related variables
	LOCAL engThrust IS 0. LOCAL engISP IS 0. LOCAL massFlow IS 0.

	// Run through the engines to get our max thrust, mass flow and ISP values
	FOR en IN landingEngines {
		SET engThrust TO engThrust + en:POSSIBLETHRUSTAT(0) * 1000. // Newtons
		SET massFlow TO massFlow + en:MAXMASSFLOW * 1000. // kg
		SET engISP TO engISP + en:VISP.
	}

	SET engISP TO engISP/landingEngines:LENGTH.
	
	LOCAL startingMass IS SHIP:MASS * 1000. // kg
	LOCAL maxDeltaV IS engISP * CONSTANT:g0 * LN(startingMass / landerDryMass).
	LOCAL maxBurnTime IS (startingMass - landerDryMass) / massFlow.

	// If our current velocity - desired velocity is more than our max deltav, we won't be able to land
	// Currently the script assumes that the continuous burn will be done with a single stage
	IF SHIP:VELOCITY:SURFACE:MAG - desiredSpeed > maxDeltaV { HUDTEXT("kOS: NOT ENOUGH DELTAV TO LAND!", 10, 2, 20, GREEN, FALSE). RETURN landingLex. }

	FUNCTION RunCycle {
		PARAMETER cycleStartTime, timeStep.

		LOCAL newTim IS cycleStartTime.
		LOCAL newVel IS VELOCITYAT(SHIP, newTim):SURFACE.
		LOCAL newPos IS -BODY:POSITION + POSITIONAT(SHIP, newTim).
		LOCAL newAlt IS BODY:ALTITUDEOF(newPos).
		LOCAL newHei IS Land_GetGeopositionAt(newTim, BODY:GEOPOSITIONOF(newPos)):TERRAINHEIGHT.
		LOCAL newMas IS startMass.
		LOCAL newAcc IS v(0,0,0).
		LOCAL newGra IS (BODY:POSITION - newPos):NORMALIZED * Gravity(newAlt).

		UNTIL FALSE {
			// update new vars
			SET newTim TO newTim + timeStep.
			SET newVel TO newVel + (newAcc * timeStep) + (newGra * timeStep).
			SET newPos TO newPos + (newVel * timeStep).// + BODY:POSITION.
			SET newAlt TO BODY:ALTITUDEOF(newPos + BODY:POSITION).
			SET newHei TO Land_GetGeopositionAt(newTim, BODY:GEOPOSITIONOF(newPos)):TERRAINHEIGHT.
			SET newMas TO newMas - (massFlow * timeStep).
			SET newAcc TO Rodrigues(-newVel, VCRS(newVel, -newPos), angle):NORMALIZED * engThrust / newMas.
			SET newGra TO (-newPos):NORMALIZED * Gravity(newAlt).
		}

		RETURN TRUE.
	}
}