@LAZYGLOBAL OFF.

// Sends a docking request to another vessel and waits for a response
FUNCTION Dock_RequestDocking {
	PARAMETER targetShipName IS "", myPortTag IS "", waitTime IS 15.

	LOCAL myPort IS FALSE.
	LOCAL targetShip IS FALSE.
	// if our port is an empty string, we just select the first docking port on the list
	IF myPortTag = "" {
		FOR port IN SHIP:DOCKINGPORTS {
			IF port:STATE = "Ready" {
				SET myPort TO port.
				BREAK.
			}
		}
	} ELSE {
		LOCAL pList IS SHIP:PARTSTAGGED(myPortTag).
		IF pList:LENGTH > 0 {
			IF pList[0]:ISTYPE("DockingPort") AND pList[0]:STATE = "Ready" {
				SET myPort TO pList[0].
			}
		}
	}

	IF myPort:ISTYPE("bool") {
		HUDTEXT("Port not found or not available", 10, 2, 20, RED, FALSE).
		RETURN FALSE.
	}

	IF targetShipName = "" {
		IF SHIP:HASTARGET AND TARGET:ISTYPE("Vessel") {
			IF TARGET:LOADED {
				SET targetShip TO TARGET.
			} ELSE {
				HUDTEXT("Target ship outside of physics range", 10, 2, 20, RED, FALSE).
				RETURN FALSE.
			}
		} ELSE {
			HUDTEXT("Target ship not specified", 10, 2, 20, RED, FALSE).
			RETURN FALSE.
		}
	} ELSE {
		FOR s IN TARGETS {
			IF s:NAME = targetShipName AND s:LOADED {
				SET targetShip TO s.
				BREAK.
			}
		}
	}

	IF targetShip:ISTYPE("bool") {
		HUDTEXT("Could not find specified ship in physics range", 10, 2, 20, RED, FALSE).
		RETURN FALSE.
	}

	LOCAL c	IS targetShip:CONNECTION.
	LOCAL request IS LEXICON("type", "DockingRequest", "nodeType", myPort:NODETYPE).
	IF NOT c:ISCONNECTED OR NOT c:SENDMESSAGE(request) {
		HUDTEXT("Could not send a docking request", 10, 2, 20, RED, FALSE).
		RETURN FALSE.
	}

	LOCAL response IS FALSE.
	LOCAL waitPeriodEnded IS FALSE.
	LOCAL sentTime IS TIME:SECONDS.

	UNTIL waitPeriodEnded {
		IF NOT SHIP:MESSAGES:EMPTY {
			FOR msg IN SHIP:MESSAGES {
				IF msg:PEEK():SENDER = targetShip AND msg:PEEK():CONTENT:ISTYPE("Lexicon")
				AND msg:PEEK():CONTENT:HASKEY("type") AND msg:PEEK():CONTENT["type"] = "DockingRequestResponse" {
					SET response TO msg:POP().
					SET waitPeriodEnded TO TRUE.
					BREAK.
				}
			}
		}

		IF TIME:SECONDS - sentTime > waitTime { SET waitPeriodEnded TO TRUE. }

		// Maybe do some stationkeeping here

		WAIT 0.
	}

	IF response:ISTYPE("bool") {
		HUDTEXT("Did not receive response from target ship", 10, 2, 20, RED, FALSE).
		RETURN FALSE.
	}

	IF NOT response:CONTENT["result"] {
		HUDTEXT("Docking request denied", 10, 2, 20, RED, FALSE).
		RETURN FALSE.
	}

	LOCAL targetPort IS FALSE.
	FOR port IN targetShip:DOCKINGPORTS {
		IF port:CID = response:CONTENT["dockingPortCID"] {
			SET targetPort TO port.
			BREAK.
		}
	}

	IF targetPort:ISTYPE("bool") {
		HUDTEXT("Could not locate docking port on target ship", 10, 2, 20, RED, FALSE).
		RETURN FALSE.
	}

	// If we got to this point, call the actuall docking function with the information we received
	Dock_DockTo(targetPort, myPort, response:CONTENT["safeDist"]).
}

// Function that actually docks to the target docking port
FUNCTION Dock_DockTo {
	PARAMETER targetDockingPort, myDockingPort, safeDist IS 250, moveSpeed IS 5.
	RCS ON. SAS OFF.

	// Make sure the safe distance is at least 50
	SET safeDist TO MAX(50, safeDist).

	// Create some variables that will be required during the docking
	LOCAL LOCK relativeVelocity TO SHIP:VELOCITY:ORBIT - targetDockingPort:SHIP:VELOCITY:ORBIT.

	// For now, just cancel any rotation and hold the current attitude
	LOCAL steer IS LOOKDIRUP(SHIP:FACING:FOREVECTOR, SHIP:FACING:TOPVECTOR).
	LOCK STEERING TO steer.

	// First check to make sure that we are outside the safe zone
	// If not then move outside and then continue with the script
	UNTIL targetDockingPort:SHIP:DISTANCE > safeDist {
		SET steer TO LOOKDIRUP(SHIP:FACING:FOREVECTOR, SHIP:FACING:TOPVECTOR).
		Translate(-targetDockingPort:SHIP:POSITION:NORMALIZED * 5 - relativeVelocity).
		WAIT 0.
	}

	// Kill our relative velocity
	UNTIL relativeVelocity:MAG < 0.1 {
		SET steer TO LOOKDIRUP(SHIP:FACING:FOREVECTOR, SHIP:FACING:TOPVECTOR).
		Translate(V(0,0,0) - relativeVelocity).
		WAIT 0.
	}
	Translate(V(0,0,0)).

	LOCAL shipAngle IS VANG(-targetDockingPort:SHIP:POSITION, targetDockingPort:NODEPOSITION - targetDockingPort:SHIP:POSITION + targetDockingPort:PORTFACING:FOREVECTOR * safeDist).
	LOCAL stationAxis IS VCRS(-targetDockingPort:SHIP:POSITION, targetDockingPort:NODEPOSITION - targetDockingPort:SHIP:POSITION + targetDockingPort:PORTFACING:FOREVECTOR * safeDist).

	LOCAL additionalWaypoints IS 0.

	IF shipAngle > 120 { SET additionalWaypoints TO 2. }
	ELSE IF shipAngle > 90 { SET additionalWaypoints TO 1. }

	LOCAL waypointStack IS STACK().

	waypointStack:PUSH(LEXICON("angle", 0, "distance", 0, "speed", 0.25, "stop", FALSE)).
	waypointStack:PUSH(LEXICON("angle", 0, "distance", 5, "speed", 0.5, "stop", FALSE)).
	waypointStack:PUSH(LEXICON("angle", 0, "distance", 25, "speed", 1, "stop", TRUE)).
	waypointStack:PUSH(LEXICON("angle", 0, "distance", 50, "speed", 5, "stop", FALSE)).
	waypointStack:PUSH(LEXICON("angle", 0, "distance", safeDist, "speed", moveSpeed, "stop", TRUE)).

	IF additionalWaypoints = 1 {
		waypointStack:PUSH(LEXICON("angle", shipAngle/2, "distance", safeDist, "speed", moveSpeed, "stop", FALSE)).
	} ELSE IF additionalWaypoints = 2 {
		waypointStack:PUSH(LEXICON("angle", shipAngle/3, "distance", safeDist, "speed", moveSpeed, "stop", FALSE)).
		waypointStack:PUSH(LEXICON("angle", (shipAngle/3) * 2, "distance", safeDist, "speed", moveSpeed, "stop", FALSE)).
	}

	// Make sure to set control from to our docking port
	myDockingPort:CONTROLFROM().

	LOCAL nextWaypointData IS waypointStack:POP().
	LOCAL nextWaypoint IS V(0,0,0).

	LOCAL done IS FALSE.
	LOCAL stopAtPosition IS TRUE.
	LOCAL stabilizeFacing IS FALSE.
	LOCAL canProceed IS FALSE.
	LOCAL desiredVelocity IS V(0,0,0).

	UNTIL done {
		IF nextWaypointData["angle"] <> 0 {
			SET nextWaypoint TO targetDockingPort:SHIP:POSITION + Rodrigues(targetDockingPort:PORTFACING:FOREVECTOR * nextWaypointData["distance"], stationAxis, nextWaypointData["angle"]).
		} ELSE IF nextWaypointData["angle"] = 0 {
			SET nextWaypoint TO -myDockingPort:NODEPOSITION + targetDockingPort:NODEPOSITION + targetDockingPort:PORTFACING:FOREVECTOR * nextWaypointData["distance"].
		}

		IF stabilizeFacing {
			SET steer TO LOOKDIRUP(-targetDockingPort:PORTFACING:FOREVECTOR, targetDockingPort:PORTFACING:TOPVECTOR).
		} ELSE {
			SET steer TO LOOKDIRUP(targetDockingPort:NODEPOSITION, targetDockingPort:PORTFACING:TOPVECTOR).
		}

		IF nextWaypoint:MAG < 0.1 AND relativeVelocity < 0.1 {
			IF stopAtPosition {
				IF VANG(SHIP:FACING:FOREVECTOR, -targetDockingPort:PORTFACING:FOREVECTOR) < 0.1
				AND VANG(SHIP:FACING:TOPVECTOR, targetDockingPort:PORTFACING:TOPVECTOR) < 0.1 {
					SET canProceed TO TRUE.
				}
			} ELSE { SET canProceed TO TRUE. }
		} ELSE IF nextWaypoint:MAG < 5 {
			IF NOT stopAtPosition { SET canProceed TO TRUE. }
		}

		// If we can proceed to the next waypoint, then get the next waypoint data
		// otherwise, continue moving towards our current waypoint.
		IF canProceed {
			Translate(V(0,0,0)).
			SET canProceed TO FALSE.
			// IF the port that we arrived at now has an angle of 0, start aiming at the docking port
			IF nextWaypointData["angle"] = 0 { SET stabilizeFacing TO TRUE. }

			IF waypointStack:LENGTH > 0 {
				SET nextWaypointData TO waypointStack:POP().
				SET stopAtPosition TO nextWaypointData["stop"].
			} ELSE {
				SET done TO TRUE.
			}
		} ELSE {
			SET desiredVelocity TO CHOOSE nextWaypoint IF nextWaypoint:MAG <= nextWaypointData["speed"] ELSE nextWaypoint:NORMALIZED * nextWaypointData["speed"].
			Translate(desiredVelocity - relativeVelocity).
		}

		// If our docking ports are atached or about to be attached, break out of the loop and unlock everything
		IF (myDockingPort:STATE = "PreAttached" AND targetDockingPort:STATE = "PreAttached" AND (targetDockingPort:NODEPOSITION - myDockingPort:NODEPOSITION):MAG < 5)
		OR (myDockingPort:HASPARTNER AND myDockingPort:PARTNER = targetDockingPort) {
			BREAK.
		}

		WAIT 0.
	}
	
	Translate(V(0,0,0)).
	UNLOCK ALL.
}

// A function that undocks the spacecraft and moves it away from the other vessel ready for de-orbiting
FUNCTION Dock_Undock {
	PARAMETER moveOff IS FALSE.
	LOCAL moveAwayDist IS 50.

	// Get a list of all docking ports on our ship/element
	LOCAL allPorts IS CORE:ELEMENT:DOCKINGPORTS.
	LOCAL ourPort IS FALSE.
	LOCAL otherPort IS FALSE.
	// For now, we undock the first docked port that we find on our element.
	// This should be updated later as it may not always be the correct port
	FOR port IN allPorts {
		IF port:HASPARTNER {
			SET otherPort TO port:PARTNER.
			SET ourPort TO port.
		}
	}
	// Make sure that we located the relevant docking ports
	IF ourPort:ISTYPE("bool") OR otherPort:ISTYPE("bool") {
		HUDTEXT("Undocking failed", 10, 2, 20, RED, FALSE).
		RETURN FALSE.
	}
	// Set the docking port to be the control part of the spacecraft for now
	ourPort:CONTROLFROM().
	WAIT 0.
	ourPort:UNDOCK().
	WAIT 0.
	SAS OFF.
	RCS ON.

	LOCK STEERING TO LOOKDIRUP(-otherPort:FACING:VECTOR, SHIP:FACING:TOPVECTOR).
	LOCAL LOCK dist TO (otherPort:NODEPOSITION - ourPort:NODEPOSITION):MAG.
	LOCAL LOCK relativeVelocity TO SHIP:VELOCITY:ORBIT - otherPort:SHIP:VELOCITY:ORBIT.
	
	UNTIL dist > 2 { Translate(otherPort:FACING:VECTOR*0.25 - relativeVelocity). }
	UNTIL dist > moveAwayDist { Translate(otherPort:FACING:VECTOR*2 - relativeVelocity). }

	// If we are maneuvering away from the station, execute code below
	IF moveOff {
		// Kill our relative velocity
		LOCK STEERING TO LOOKDIRUP(SHIP:FACING:FOREVECTOR, SHIP:FACING:TOPVECTOR).
		UNTIL relativeVelocity:MAG < 0.1 {
			Translate(V(0,0,0) - relativeVelocity).
			WAIT 0.
		}
		Translate(V(0,0,0)).

		// Possible directions
		LOCAL LOCK pro TO SHIP:VELOCITY:ORBIT:NORMALIZED + BODY:POSITION:NORMALIZED.
		LOCAL LOCK retro TO -SHIP:VELOCITY:ORBIT:NORMALIZED + BODY:POSITION:NORMALIZED.
		LOCAL LOCK proFlat TO SHIP:VELOCITY:ORBIT:NORMALIZED.
		LOCAL LOCK retroFlat TO -SHIP:VELOCITY:ORBIT:NORMALIZED.

		// Decide whether to move away in prograde or retrograde direction
		IF VANG(pro, otherPort) > VANG(retro, otherPort) {
			IF SHIP:ALTITUDE > otherPort:SHIP:ALTITUDE {
				LOCK STEERING TO LOOKDIRUP(proFlat, SHIP:FACING:TOPVECTOR).
				WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR, proFlat) < 0.1. WAIT 2.
				UNTIL dist > 150 {
					Translate(proFlat*5 - relativeVelocity).
					WAIT 0.
				}
				Translate(V(0,0,0)).
			}
			LOCK STEERING TO LOOKDIRUP(pro, SHIP:FACING:TOPVECTOR).
			WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR, pro) < 0.1. WAIT 2.
			UNTIL dist > 300 {
				Translate(pro*5 - relativeVelocity).
				WAIT 0.
			}
			Translate(V(0,0,0)).
		} ELSE {
			IF SHIP:ALTITUDE > otherPort:SHIP:ALTITUDE {
				LOCK STEERING TO LOOKDIRUP(retroFlat, SHIP:FACING:TOPVECTOR).
				WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR, retroFlat) < 0.1. WAIT 2.
				UNTIL dist > 150 {
					Translate(retroFlat*5 - relativeVelocity).
					WAIT 0.
				}
				Translate(V(0,0,0)).
			}
			LOCK STEERING TO LOOKDIRUP(retro, SHIP:FACING:TOPVECTOR).
			WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR, retro) < 0.1. WAIT 2.
			UNTIL dist > 300 {
				Translate(retro*5 - relativeVelocity).
				WAIT 0.
			}
			Translate(V(0,0,0)).
		}
	}
	
	// Kill our relative velocity
	LOCK STEERING TO LOOKDIRUP(SHIP:FACING:FOREVECTOR, SHIP:FACING:TOPVECTOR).
	UNTIL relativeVelocity:MAG < 0.1 {
		Translate(V(0,0,0) - relativeVelocity).
		WAIT 0.
	}
	Translate(V(0,0,0)).
	RETURN TRUE.
}

// A function that will handle translation in space
FUNCTION Translate {
	PARAMETER vector.
	// Experimenting with either having a vector of lenght of 1 or 0.75
	// Will need to test how translation and rotation play with each other
	IF vector:MAG > 1 SET vector TO vector:NORMALIZED.
	//IF vector:MAG > 0.75 SET vector TO vector:NORMALIZED * 0.75.

	SET SHIP:CONTROL:FORE TO vector * SHIP:FACING:FOREVECTOR.
	SET SHIP:CONTROL:TOP TO vector * SHIP:FACING:TOPVECTOR.
	SET SHIP:CONTROL:STARBOARD TO vector * SHIP:FACING:STARVECTOR.
}