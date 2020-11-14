@LAZYGLOBAL OFF.
WAIT UNTIL SHIP:UNPACKED.
CLEARSCREEN.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
SET VOLUME(1):NAME TO SHIP:NAME + "_" + CORE:TAG.
LOCAL version IS 1.
PRINT "CPU Name:          " + VOLUME(1):NAME AT(3,1).
PRINT "Currently Running: ProbeOS v" + version AT(3,2).
//	Setting up directories
LOCAL systemUpdateDir IS "0:/boot/".
LOCAL configUpdateDir IS "0:/configUpdates/".
LOCAL missionUpdateDir IS "0:/missionUpdates/".
GLOBAL uploadDir IS "0:/missionUploads/".
GLOBAL libsDir IS "0:/lib/".
LOCAL bootDir IS "1:/boot/".
LOCAL configDir IS "1:/config/".
LOCAL missionDir IS "1:/mission/".
LOCAL downloadsDir IS "1:/downloads/".
GLOBAL tempDir IS "1:/temp/".	// This is where all libraries and temporary files should be saved. It will be cleared after each mission script is executed.

LOCAL currentSystemVersion IS "probeOS_001.ks".
LOCAL updateFile IS VOLUME(1):NAME + "_missionUpdate.ks".
LOCAL configFile IS VOLUME(1):NAME + "_config.ks".
LOCAL toDownload IS LIST().

LOCAL configured IS FALSE.
GLOBAL steeringLocked IS FALSE.
GLOBAL vehicle IS LEXICON().
GLOBAL missionInProgress IS EXISTS(tempDir + "missionInProgress.ks").

IF NOT EXISTS(configUpdateDir) { CREATEDIR(configUpdateDir). }
IF NOT EXISTS(missionUpdateDir) { CREATEDIR(missionUpdateDir). }
IF NOT EXISTS(uploadDir) { CREATEDIR(uploadDir). }
IF NOT EXISTS(bootDir) { CREATEDIR(bootDir). }
IF NOT EXISTS(configDir) { CREATEDIR(configDir). }
IF NOT EXISTS(missionDir) { CREATEDIR(missionDir). }
IF NOT EXISTS(downloadsDir) { CREATEDIR(downloadsDir). }
IF NOT EXISTS(tempDir) { CREATEDIR(tempDir). }
IF NOT EXISTS(libsDir) { CREATEDIR(libsDir). }

// Delete all temporary files from disk.
FUNCTION ClearTempFiles {
	FOR f IN OPEN(tempDir) {
		DELETEPATH(tempDir+f:NAME).
	}
}

// All files except the boot file.
FUNCTION SoftReset {
	SWITCH TO 1.
	LOCAL allFiles IS LIST().
	LIST FILES IN allFiles.
	FOR f IN allFiles {
		IF NOT f:ISFILE {
			IF f:NAME <> "boot" { DELETEPATH("1:/"+f:NAME). }
		} ELSE { DELETEPATH("1:/"+f:NAME). }
	}
	FOR f IN OPEN(bootDir) {
		IF f:NAME <> currentSystemVersion AND f:NAME <> "probeOS.ks" {
			DELETEPATH(bootDir+f:NAME).
		}
	}
	REBOOT.
}

// Wipes everything from the disk including ProbeOS system
// Should only be used to bring the CPU to a clean state
FUNCTION HardReset {
	SWITCH TO 1.
	LOCAL allFiles IS LIST().
	LIST FILES IN allFiles.
	FOR f IN allFiles {
		DELETEPATH("1:/"+f:NAME).
	}
	SET CORE:BOOTFILENAME TO "None".
	REBOOT.
}

FUNCTION Notify {
	PARAMETER message, msgDelay is 5, color IS YELLOW.
	HUDTEXT("kOS: " + message, msgDelay, 2, 20, color, false).
}

FUNCTION DownloadFile {
	PARAMETER fileDir, fileName, isTemp IS FALSE.
	WAIT 2.
	IF NOT HOMECONNECTION:ISCONNECTED {
		Notify("ERROR: Donwloading update failed. Connection lost.", 5, RED).
		RETURN FALSE.
	} ELSE IF NOT EXISTS(fileDir + fileName) {
		Notify("ERROR: Donwloading update failed. File " + fileName + " not found.", 5, RED).
		RETURN FALSE.
	} ELSE {
		IF EXISTS(downloadsDir + fileName) { DELETEPATH(downloadsDir + fileName). }
		COPYPATH(fileDir + fileName, downloadsDir + fileName).
		IF fileName:CONTAINS("_missionUpdate.ks") OR fileName:CONTAINS("_config.ks") { MOVEPATH(fileDir + fileName, fileDir + "uploaded_" + fileName). }
		IF isTemp { MOVEPATH(downloadsDir + fileName, tempDir + fileName). }
		RETURN TRUE.
	}
}

FUNCTION DownloadLib {
	PARAMETER fileName.
	RETURN DownloadFile(libsDir, fileName, TRUE).
}

FUNCTION SystemUpdate {
	PARAMETER fileName.
	Notify("Downloading system update.").
	IF DownloadFile(systemUpdateDir, fileName) {
		DELETEPATH(bootDir + "probeOS.ks").
		DELETEPATH(bootDir + currentSystemVersion).
		MOVEPATH(downloadsDir + fileName, bootDir + "probeOS.ks").
		Notify("Update complete! Rebooting...", 5, GREEN).
		WAIT 4.
		REBOOT.
	}
}

FUNCTION ConfigUpdate {
	Notify("Downloading config update.").
	IF DownloadFile(configUpdateDir, configFile) {
		IF EXISTS(configDir + configFile) { DELETEPATH(configDir + configFile). }
		MOVEPATH(downloadsDir + configFile, configDir + configFile).
		DELETEPATH(downloadsDir + configFile).
		Notify("Download complete! Configuring...", 5, GREEN).
		WAIT 4.
		RUNPATH(configDir + configFile).
		SET configured TO TRUE.
		PRINT "Configuration:     Loaded    " AT(3,3).
	}
}

FUNCTION MissionUpdate {
	Notify("Downloading mission update.").
	IF DownloadFile(missionUpdateDir, updateFile) {
		IF EXISTS(missionDir + updateFile) { DELETEPATH(missionDir + updateFile). }
		MOVEPATH(downloadsDir + updateFile, missionDir + updateFile).
		DELETEPATH(downloadsDir + updateFile).
		Notify("Download complete! Running instructions...", 5, GREEN).
		WAIT 4.
		RunMission().
	}
}

FUNCTION RunMission {
	PARAMETER dir IS missionDir, file IS updateFile.
	RUNPATH(dir + file).	// Run the mission file
	ClearTempFiles().		// Clear all temporary files
	REBOOT.
}

FUNCTION GetUpdates {
	//	Check if new version of boot file exists
	IF toDownload:EMPTY {
		FOR f IN OPEN(systemUpdateDir) {
			IF f:NAME:STARTSWITH("probeOS_") AND f:NAME <> currentSystemVersion {
				IF f:NAME:SUBSTRING(8, f:NAME:LENGTH()-11):TONUMBER() > version {
					toDownload:ADD(LEXICON("type", "boot", "name", f:NAME, "time", TIME:SECONDS)).
					WHEN toDownload[0]["time"] < TIME:SECONDS THEN {
						KUNIVERSE:TIMEWARP:CANCELWARP().
						WHEN KUNIVERSE:TIMEWARP:ISSETTLED THEN {
							LOCAL n IS toDownload[0]["name"].
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
			toDownload:ADD(LEXICON("type", "config", "name", configFile, "time", TIME:SECONDS)).
			WHEN toDownload[0]["time"] < TIME:SECONDS THEN {
				KUNIVERSE:TIMEWARP:CANCELWARP().
				WHEN KUNIVERSE:TIMEWARP:ISSETTLED THEN {
					toDownload:REMOVE(0).
					ConfigUpdate().
				}
			}
		} ELSE IF EXISTS(missionUpdateDir + updateFile) {	//	If no boot/config file update needed, check for mission updates
			toDownload:ADD(LEXICON("type", "mission", "name", updateFile, "time", TIME:SECONDS)).
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

FUNCTION StandBy {
	IF vehicle:HASKEY("standby-facing") {
		IF (VANG(SHIP:FACING:VECTOR, vehicle["standby-facing"]["facing-vector"]) > 1) OR (SHIP:ANGULARVEL:MAG > 0.01) {
			PRINT "Standby Tasks:     Facing Sun" AT(3,5).
			vehicle["standby-facing"]["face"]().
		}
	}
	PRINT "Standby Tasks:     None          " AT(3,5).
}

// Check for an on-going mission and let it complete.
IF missionInProgress {
	RunMission().
}

IF EXISTS(configDir + configFile) {
	RUNPATH(configDir + configFile).
	SET configured TO TRUE.
	PRINT "Configuration:     Loaded    " AT(3,3).
} ELSE { PRINT "Configuration:     Not Loaded" AT(3,3). }

Notify("System loaded successfully! Running ProbeOS v" + version + ".").

PRINT "Free Disk Space:   " + VOLUME(1):FREESPACE + "/" + VOLUME(1):CAPACITY + " " + ROUND(VOLUME(1):FREESPACE/VOLUME(1):CAPACITY*100,1) + "%              " AT(3,6).

UNTIL FALSE {
	IF HOMECONNECTION:ISCONNECTED {
		PRINT "Connection Status: Connected     " AT(3,4).
		GetUpdates().
	} ELSE {
		PRINT "Connection Status: Not Connected " AT(3,4).
		WAIT UNTIL HOMECONNECTION:ISCONNECTED.
	}
	IF KUNIVERSE:TIMEWARP:MODE = "RAILS" AND KUNIVERSE:TIMEWARP:RATE > 1 {
		WAIT KUNIVERSE:TIMEWARP:RATE.
	} ELSE {
		IF configured { StandBy(). }
		WAIT 10.
	}
}