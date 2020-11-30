@LAZYGLOBAL OFF.

// The passive docking script is meant to only decide which docking port to assign to
// incoming spacecraft. Holding an orientation should be done via a separate stationkeeping script
FUNCTION Dock_CheckForRequests {
	PARAMETER safeDist IS 100.

	IF NOT SHIP:MESSAGES:EMPTY {
		LOCAL msg IS SHIP:MESSAGES:POP().
		IF msg:HASSENDER {
			LOCAL content IS msg:CONTENT.
			IF content:ISTYPE("Lexicon") AND content:HASKEY("type") AND content:HASKEY("nodeType") {
				IF content:type = "DockingRequest" {
					LOCAL availablePorts IS LIST().
					LOCAL selectedPort IS FALSE.
					FOR port IN SHIP:DOCKINGPORTS {
						IF port:NODETYPE = content["nodeType"] AND port:STATE = "Ready" {
							availablePorts:ADD(port).
						}
					}
					IF availablePorts:LENGTH = 1 { SET selectedPort TO availablePorts[0]:CID. }
					IF availablePorts:LENGTH > 1 {
						LOCAL closestDist IS -1.
						FOR port IN availablePorts {
							LOCAL dist IS ((port:NODEPOSITION + port:PORTFACING:FOREVECTOR * safeDist) - msg:SENDER:POSITION):MAG.
							IF dist < closestDist OR closestDist = -1 {
								SET selectedPort TO availablePorts[0]:CID.
								SET closestDist TO dist.
							}
						}
					}
					LOCAL response IS LEXICON("type", "DockingRequestResponse", "result", selectedPort:ISTYPE("string")).
					IF response:result {
						response:ADD("dockingPortCID", selectedPort).
						response:ADD("safeDist", safeDist).
					}
					
					LOCAL c IS msg:SENDER:CONNECTION.
					IF c:ISCONNECTED {
						IF c:SENDMESSAGE(response) {
							IF NOT response:result { RETURN FALSE. }
							RETURN TRUE.
						}
					}
				}
			}
		}
	}

	RETURN FALSE.
}

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
}

// Function that actually docks to the target docking port
FUNCTION Dock_DockTo {
	PARAMETER targetDockingPort, myDockingPort, safeDist IS 250.

	// First check to make sure that we are outside the safe zone
	// If not then move outside and then continue with the script

	LOCAL shipAngle IS VANG(-targetDockingPort:SHIP:POSITION, targetDockingPort:NODEPOSITION - targetDockingPort:SHIP:POSITION + targetDockingPort:PORTFACING:FOREVECTOR * safeDist).
	LOCAL stationAxis IS VCRS(-targetDockingPort:SHIP:POSITION, targetDockingPort:NODEPOSITION - targetDockingPort:SHIP:POSITION + targetDockingPort:PORTFACING:FOREVECTOR * safeDist).

	LOCAL totalWaypoints IS 2.

	IF shipAngle > 120 { SET totalWaypoints TO 4. }
	ELSE IF shipAngle > 90 { SET totalWaypoints TO 3. }

	LOCAL waypointStack IS STACK().

	waypointStack:ADD(0).
	waypointStack:ADD(0).

	IF totalWaypoints = 3 { 
		waypointStack:ADD(shipAngle/2).
	} ELSE IF totalWaypoints = 4 {
		waypointStack:ADD(shipAngle/3).
		waypointStack:ADD((shipAngle/3) * 2).
	}

	// Make sure to set control from to our docking port

	LOCAL nextWaypointAngle IS 0.
	LOCAL nextWaypoint IS V(0,0,0).

	LOCAL done IS FALSE.
	LOCAL steer IS PROGRADE.
	LOCK STEERING TO steer.

	UNTIL done {
		IF totalWaypoints > 2 AND waypointStack:LENGTH > 2 {
			SET nextWaypoint TO targetDockingPort:SHIP:POSITION + Rodrigues(targetDockingPort:PORTFACING:FOREVECTOR, stationAxis, nextWaypointAngle) * safeDist.
		} ELSE IF waypointStack:LENGTH > 0 {
			SET nextWaypoint TO -myDockingPort:NODEPOSITION + targetDockingPort:NODEPOSITION + Rodrigues(targetDockingPort:PORTFACING:FOREVECTOR, stationAxis, nextWaypointAngle) * safeDist.
		} ELSE {
			SET nextWaypoint TO -myDockingPort:NODEPOSITION + targetDockingPort:NODEPOSITION + Rodrigues(targetDockingPort:PORTFACING:FOREVECTOR, stationAxis, nextWaypointAngle) * 25.
		}

		IF nextWaypoint:MAG > 10 {
			SET steer TO LOOKDIRUP(nextWaypoint, SHIP:FACING:TOPVECTOR).
		}
	}
}