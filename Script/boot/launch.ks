CLEARSCREEN.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.

SET CONFIG:IPU TO 2000.

// Run the required library files
RUNPATH("0:/lib/telemetry.ks").
RUNPATH("0:/lib/maneuvers.ks").
RUNPATH("0:/lib/misc.ks").

//	If necessary, print an error message and crash the program by trying to use undefined variables.
FUNCTION ForceCrash {
	PARAMETER msg.
	CLEARSCREEN.
	PRINT " ".
	PRINT "ERROR!".
	PRINT " ".
	PRINT msg.
	PRINT " ".
	PRINT "Crashing...".
	PRINT " ".
	LOCAL error IS undefinedVariable.
}

WAIT UNTIL AG10.

//	Declare variables
GLOBAL runmode IS 0.
GLOBAL subRunmode IS 0.
GLOBAL currentAltitude IS 0.
GLOBAL launchSiteDistance IS 0.
GLOBAL launchSiteAltitude IS SHIP:ALTITUDE.
LOCAL launchSitePosition IS SHIP:GEOPOSITION.
GLOBAL targetApoapsis IS 0.
GLOBAL launchDirection IS 0.
GLOBAL launchGLimit IS 0.
LOCAL maximumThrust IS 0.
//	Gravity turn vairiables
LOCAL turnSpeed IS 30.
LOCAL turnAltitude IS 0.
LOCAL turnEndSpeed IS 1300.
LOCAL turnEndAltitude IS 40000.
//	Steering variables
LOCAL tval IS 0.
LOCAL steer IS UP.
//	Time tracking variables
LOCAL dT IS 0.				//	Delta time
GLOBAL mT IS TIME:SECONDS.	//	Current time
GLOBAL lT IS 0.				//	Until/since launch
LOCAL pT IS 0.				//	Previous tick time
LOCAL eventTime IS 0.
LOCAL event IS FALSE.
LOCAL nd IS 0.
LOCAL missionSet IS FALSE.

//	Setting up UI
GLOBAL UILex IS LEXICON("time", LIST(), "message", LIST()).
GLOBAL UILexLength IS 0.
CreateUI().

//	A wrapper function that calls all other functions
FUNCTION Main {
	UpdateVars("start").
	IF 		runmode = 0 { Prelaunch().		}
	ELSE IF runmode = 1 { Launch().			}
	ELSE IF runmode = 2 { Coasting().		}
	ELSE IF runmode = 3 { Circularization().}
	ELSE IF runmode = 4 { Postlaunch().		}
	RefreshUI().
	UpdateVars("end").
	IF runmode = 5 { RETURN TRUE. } ELSE { RETURN FALSE. }
}

//	Updating varibales before and after every iteration
FUNCTION UpdateVars {
	PARAMETER type.

	IF type = "start" {
		SET mT TO TIME:SECONDS.
		SET dT TO mT - pT.
		SET currentAltitude TO SHIP:ALTITUDE.
		SET launchSiteDistance TO (launchSitePosition:POSITION - SHIP:GEOPOSITION:ALTITUDEPOSITION(launchSiteAltitude)):MAG.//	Downrange distance
	} ELSE IF type = "end" {
		SET pT TO mT.
	}
}

//	Handles things that happen before launch
FUNCTION Prelaunch {
	IF subRunmode = 0 {			//	Request launch data from user
		IF missionSet {
			SET subRunmode TO 1.
			SET lT TO TIME:SECONDS + 10. // CHANGE THIS!!!
			AddUIMessage("Launching in " + ROUND(lT - mT) + " seconds!").
		} ELSE {
			GetMissionProfile().
			SET missionSet TO TRUE.
		}
	} ELSE IF subRunmode = 1 {	//	Ignite engines at T-2 seconds
		IF mT > lT - 2 {
			LOCK THROTTLE TO tval.
			LOCK STEERING TO steer.
			SET tval TO 1.
			STAGE.
			SET maximumThrust TO SHIP:MAXTHRUST.
			AddUIMessage("Engine Ignition!").
			SET subRunmode TO 2.
		}
	} ELSE IF subRunmode = 2 {
		IF mT > lT {
			SET runmode TO 1.
			SET subRunmode TO 0.
			STAGE.
			SET maximumThrust TO SHIP:MAXTHRUST.
			AddUIMessage("Liftoff!").

			// Set a trigger for deploying the fairing/LAS
			WHEN SHIP:ALTITUDE > 40000 THEN {
				LIGHTS ON.
				AddUIMessage("Fairing deployment.").
			}
			// Set a trigger for staging
			WHEN SHIP:MAXTHRUST < maximumThrust * 0.95 OR SHIP:MAXTHRUST = 0 THEN {
				WAIT 0.5.
				STAGE.
				AddUIMessage("Stage separation.").
				SET maximumThrust TO SHIP:MAXTHRUST.
				PRESERVE.
			}
		}
	}
}

//	Handles things that happen during launch
FUNCTION Launch {
	//	Handle G limit during ascent
	IF subRunmode < 2{
		IF launchGLimit <> 0 AND ShipTWR() > 0 {
			SET tval TO MIN(1, MAX(0.2, launchGLimit/ShipTWR())).
			IF NOT event { SET event TO TRUE. AddUIMessage("Throttling down to maintain " + launchGLimit + "Gs."). }
		} ELSE {
			SET tval TO 1.
		}
	}

	IF subRunmode = 0 {	//	Wait until over 100 meters above ground before pitching over
		SET steer TO HEADING(launchDirection, 90).
		
		IF SHIP:VELOCITY:SURFACE:MAG > turnSpeed {
			SET turnAltitude TO currentAltitude.
			AddUIMessage("Pitching downrange.").
			SET subRunmode TO 1.
		}
	} ELSE IF subRunmode = 1 {	//	Execute the graviti turn
		LOCAL speedComponent IS 1 - (SHIP:VELOCITY:SURFACE:MAG - turnSpeed) / turnEndSpeed.
		LOCAL altitudeComponent IS 1 - (currentAltitude - turnAltitude) / turnEndAltitude.
		LOCAL pitch IS MAX(5, MIN(90, 90 * (speedComponent * 0.6 + altitudeComponent * 0.4))).

		SET steer TO HEADING(launchDirection, pitch).

		IF SHIP:APOAPSIS >= targetApoapsis - 2500 {
			SET subRunmode TO 2.
		}
	} ELSE IF subRunmode = 2 {	//	Approach the target apoapsis without crossing it by too much
		SET tval TO MAX(0.1, MIN(tval, (targetApoapsis - SHIP:APOAPSIS) / 2500)).
		IF SHIP:APOAPSIS >= targetApoapsis {
			AddUIMessage("Coasting to space.").
			SET tval TO 0.
			SET subRunmode TO 0.
			SET runmode TO 2.
		}
	}
}

//	Coast to space and raise apoapsis back to the target altitude
FUNCTION Coasting {
	// Coast untill out of atmosphere
	IF subRunmode = 0 {
		IF currentAltitude > 70000 {
			KUNIVERSE:TIMEWARP:CANCELWARP().
			SET subRunmode TO 1.
		}
	} ELSE IF subRunmode = 1 {
		IF KUNIVERSE:TIMEWARP:ISSETTLED {
			SET subRunmode TO 2.
		}
	} ELSE IF subRunmode = 2 {	// Increase apoapsis back to the target altitude
		IF SHIP:APOAPSIS < targetApoapsis {
			SET tval TO MAX(0.05, MIN(MIN(1, launchGLimit/ShipTWR()), (targetApoapsis - SHIP:APOAPSIS) / 2500)).
		} ELSE {
			SET tval TO 0.
			SET subRunmode TO 0.
			SET runmode TO 3.
		}
	}
}

//	Handles circularization - DUH!
FUNCTION Circularization {
	IF subRunmode = 0 {
		// Create a maneuver node at apoapsis for circularization
		LOCAL circDeltaV IS OrbitalVelocityAt(SHIP:APOAPSIS) - VELOCITYAT(SHIP, mt + ETA:APOAPSIS):ORBIT:MAG.
		SET nd TO NODE(mT + ETA:APOAPSIS, 0, 0, circDeltaV).
		ADD(nd).
		AddUIMessage("Maneuver node created. Executing.").
		SET subRunmode TO 1.
	} ELSE IF subRunmode = 1 {	// Use maneuver node to circularize at the perfect altitude
		ExecNode(TRUE).
		LOCK STEERING TO steer.
		LOCK THROTTLE TO tval.
		SET steer TO SHIP:VELOCITY:ORBIT.
		WAIT 5.
		AddUIMessage("Maneuver complete.").
		SET runmode TO 4.
	}
}

//	Handles stuff that happens after the vehicle is in orbit
FUNCTION Postlaunch {

	// Payload separation, deorbiting etc.

	SET runmode TO 5.
}

//	Waiting 1 physics tick so that everything updates
WAIT 0.

LOCAL finished IS FALSE.

//	Program loop
UNTIL finished {
	SET finished TO Main().
	WAIT 0.
}

//	Once done, release control of everything
UNLOCK ALL.