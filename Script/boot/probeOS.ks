@LAZYGLOBAL OFF.
CLEARSCREEN.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
SET VOLUME(1):NAME TO SHIP:NAME + "_" + CORE:TAG.
LOCAL version IS 1.
PRINT "CPU Name:          " + VOLUME(1:NAME) AT(3,1).
PRINT "Currently Running: ProbeOS v" + version AT(3,2).
//	Setting up directories
LOCAL systemUpdateDir IS "0:/boot/".
LOCAL configUpdateDir IS "0:/configUpdates/".
LOCAL missionUpdateDir IS "0:/missionUpdates/".
LOCAL uploadDir IS "0:/missionUploads/".
LOCAL bootDir IS "1:/boot/".
LOCAL configDir IS "1:/config/".
LOCAL missionDir IS "1:/mission/".
LOCAL downloadsDir IS "1:/downloads/".

LOCAL currentSystemVersion IS "probeOS_001.ks".
LOCAL updateFile IS VOLUME(1):NAME + "_missionUpdate.ks".
LOCAL configFile IS VOLUME(1):NAME + "_config.ks".
LOCAL toDownload IS LIST().

IF NOT EXISTS(configUpdateDir) { CREATEDIR(configUpdateDir). }
IF NOT EXISTS(missionUpdateDir) { CREATEDIR(missionUpdateDir). }
IF NOT EXISTS(uploadDir) { CREATEDIR(uploadDir). }
IF NOT EXISTS(bootDir) { CREATEDIR(bootDir). }
IF NOT EXISTS(configDir) { CREATEDIR(configDir). }
IF NOT EXISTS(missionDir) { CREATEDIR(missionDir). }
IF NOT EXISTS(downloadsDir) { CREATEDIR(downloadsDir). }

//	Get signal delay to KSC
FUNCTION Delay {
	RETURN ADDONS:RT:DELAY(SHIP)*2.
}

FUNCTION Notify {
  PARAMETER message, delay is 5, color IS YELLOW.
  HUDTEXT("kOS: " + message, delay, 2, 50, color, false).
}

FUNCTION DownloadFile {
	PARAMETER fileDir, fileName.
	WAIT 2.
	IF NOT ADDONS:RT:HASCONNECTION(SHIP) {
		Notify("ERROR: Donwloading update failed. Connection lost.", 5, RED).
		RETURN FALSE.
	} ELSE IF NOT EXISTS(fileDir + fileName) {
		Notify("ERROR: Donwloading update failed. File not found.", 5, RED).
		RETURN FALSE.
	} ELSE {
		IF EXISTS(downloadsDir + fileName) { DELETEPATH(downloadsDir + fileName). }
		COPYPATH(fileDir + fileName, downloadsDir + fileName).
		IF fileName:CONTAINS("_missionUpdate.ks") OR fileName:CONTAINS("_config.ks") { MOVEPATH(fileDir + fileName, fileDir + "uploaded_" + fileName). }
		RETURN TRUE.
	}
}

FUNCTION SystemUpdate {
	PARAMETER fileName.
	Notify("Downloading system update.").
	IF DownloadFile(systemUpdateDir, fileName) {
		DELETEPATH(bootDir + "probeOS.ks").
		MOVEPATH(downloadsDir + fileName, bootDir + "probeOS.ks").
		Notify("Update complete! Rebooting...", 5, GREEN).
		WAIT 2.
		REBOOT.
	}
}

FUNCTION ConfigUpdate {
	Notify("Downloading config update.").
	IF DownloadFile(configUpdateDir, configFile) {
		IF EXISTS(configDir + configFile) { DELETEPATH(configDir + configFile). }
		MOVEPATH(downloadsDir + configFile, configDir + configFile).
		DELETEPATH(downloadsDir + configFile).
		Notify("Download complete! Rebooting...", 5, GREEN).
		WAIT 2.
		REBOOT.
	}
}

FUNCTION MissionUpdate {
	Notify("Downloading mission update.").
	IF DownloadFile(missionUpdateDir, updateFile) {
		IF EXISTS(missionDir + updateFile) { DELETEPATH(missionDir + updateFile). }
		MOVEPATH(downloadsDir + updateFile, missionDir + updateFile).
		DELETEPATH(downloadsDir + updateFile).
		Notify("Download complete! Running instructions...", 5, GREEN).
		WAIT 2.
		RUNPATH(missionDir + updateFile).
		REBOOT.
	}
}

FUNCTION GetUpdates {
	//	Check if new version of boot file exists
	IF toDownload:EMPTY {
		FOR f IN VOLUME(0):OPEN("boot/") {
			IF f:NAME:STARTSWITH("probeOS_") AND f:NAME <> currentSystemVersion {
				IF f:NAME:SUBSTRING(8, f:NAME:LENGTH()-11):TONUMBER() > version {
					toDownload:ADD(LEXICON("type", "boot", "name", f:NAME, "time" TIME:SECONDS + Delay())).
					WHEN toDownload[0]["time"] < TIME:SECONDS THEN {
						KUNIVERSE:TIMEWARP:CANCELWARP().
						WHEN KUNIVERSE:TIMEWARP:ISSETTLED THEN {
							LOCAL n = toDownload[0]["name"].
							toDownload:REMOVE(0).
							SystemUpdate(n).
						}
					}
				}
			}
		}
	}
	IF toDownload:EMPTY {
		//	If no boot file update needed, check for config updates
		IF EXISTS(configUpdateDir + configFile) {
			toDownload:ADD(LEXICON("type", "config", "name", f:NAME, "time" TIME:SECONDS + Delay())).
			WHEN toDownload[0]["time"] < TIME:SECONDS THEN {
				KUNIVERSE:TIMEWARP:CANCELWARP().
				WHEN KUNIVERSE:TIMEWARP:ISSETTLED THEN {
					toDownload:REMOVE(0).
					ConfigUpdate().
				}
			}
		} ELSE IF EXISTS(updateDir + updateFile) {	//	If no boot/config file update needed, check for mission updates
			toDownload:ADD(LEXICON("type", "mission", "name", f:NAME, "time" TIME:SECONDS + Delay())).
			WHEN toDownload[0]["time"] < TIME:SECONDS THEN {
				KUNIVERSE:TIMEWARP:CANCELWARP().
				WHEN KUNIVERSE:TIMEWARP:ISSETTLED THEN {
					toDownload:REMOVE(0).
					MissionUpdate().
				}
			}
		}
	}
}

IF EXISTS(configDir + configFile) {
	RUNPATH(configDir + configFile).
	PRINT "Configuration:     Loaded" AT(3,3).
} ELSE { PRINT "Configuration:     Not Loaded" AT(3,3). }

Notify("System loaded successfully! Running ProbeOS v" + version + ".").

UNTIL FALSE {
	PRINT "Signal Delay:      " + ROUND(Delay(),2) + "s       " AT(3,5).
	IF ADDONS:RT:HASCONNECTION(SHIP) {
		PRINT "Connection Status: Connected!    " AT(3,4).
		GetUpdates().
	} ELSE {
		PRINT "Connection Status: Not Connected!" AT(3,4).
		WAIT UNTIL ADDONS:RT:HASCONNECTION(SHIP).
	}
	IF KUNIVERSE:TIMEWARP:MODE = "RAILS" AND KUNIVERSE:TIMEWARP:RATE > 0 {
		WAIT KUNIVERSE:TIMEWARP:RATE.
	} ELSE {
		WAIT 5.
	}
}