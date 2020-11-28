@LAZYGLOBAL OFF.

// The passive docking script is meant to only decide which docking port to assign to
// incoming spacecraft. Holding an orientation should be done via a separate stationkeeping script
FUNCTION Dock_CheckForRequests {
	PARAMETER safeDist IS 100.

	IF NOT SHIP:MESSAGES:EMPTY {
		LOCAL msg IS SHIP:MESSAGES:POP().
		IF msg:HASSENDER {
			LOCAL content IS msg:CONTENT.
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
				LOCAL returnLex IS LEXICON("type", "DockingRequestResponse", "result", selectedPort:ISTYPE("string")).
				IF selectedPort:ISTYPE("string") {
					returnLex:ADD("dockingPortCID", selectedPort).
				}
				RETURN returnLex.
			}
		}
	}
}