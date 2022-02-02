@LAZYGLOBAL OFF.
WAIT UNTIL SHIP:UNPACKED.
CLEARSCREEN.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
SET VOLUME(1):NAME TO CHOOSE SHIP:NAME IF CORE:TAG = "" ELSE SHIP:NAME + "_" + CORE:TAG.
LOCAL version IS 1.
LOCAL bootTime IS TIME:SECONDS.
CreateUI().
PrintValue(VOLUME(1):NAME, 1, 2).
PrintValue("ProbeOS v" + version, 3, 25).
//	Setting up directories
LOCAL systemUpdateDir IS "0:/boot/".
LOCAL missionUpdateDir IS "0:/missionUpdates/".
GLOBAL uploadDir IS "0:/missionUploads/".
GLOBAL libsDir IS "0:/lib/".
LOCAL bootDir IS "1:/boot/".
LOCAL missionDir IS "1:/mission/".
LOCAL downloadsDir IS "1:/downloads/".
GLOBAL tempDir IS "1:/temp/".	// This is where all libraries and temporary files should be saved. It will be cleared after each mission script is executed.

// Common file names
LOCAL currentSystemVersion IS "probeOS_001.ks".
LOCAL updateFile IS VOLUME(1):NAME + "_missionUpdate.ks".
LOCAL altUpdateFile IS "activeVessel_missionUpdate.ks".
GLOBAL missionInProgress IS EXISTS(tempDir + "missionInProgress.ks").

// Config variables
LOCAL configured IS FALSE.
LOCAL hasSolars IS FALSE.
LOCAL solarsVector IS V(0,0,0).
LOCAL RCSForRotation IS FALSE.

// Vehicle state
GLOBAL steeringLocked IS FALSE.

IF NOT EXISTS(missionUpdateDir) { CREATEDIR(missionUpdateDir). }
IF NOT EXISTS(uploadDir) { CREATEDIR(uploadDir). }
IF NOT EXISTS(bootDir) { CREATEDIR(bootDir). }
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
	PARAMETER fileDir, fileName, isTemp IS FALSE, compilingRequired IS FALSE.
	WAIT 2.
	IF NOT HOMECONNECTION:ISCONNECTED {
		Notify("ERROR: Donwloading update failed. Connection lost.", 5, RED).
		RETURN FALSE.
	} ELSE IF NOT EXISTS(fileDir + fileName) {
		Notify("ERROR: Donwloading update failed. File " + fileName + " not found.", 5, RED).
		RETURN FALSE.
	} ELSE {
		LOCAL newFileName IS fileName.
		IF EXISTS(downloadsDir + fileName) { DELETEPATH(downloadsDir + fileName). }
		IF compilingRequired {
			SET newFileName TO fileName + "m".
			COMPILE fileDir + fileName TO downloadsDir + newFileName.
		} ELSE { COPYPATH(fileDir + fileName, downloadsDir + fileName). }
		IF fileName:CONTAINS("_missionUpdate.ks") OR fileName:CONTAINS("_config.ks") { MOVEPATH(fileDir + fileName, fileDir + "uploaded_" + fileName). }
		IF isTemp { MOVEPATH(downloadsDir + newFileName, tempDir + newFileName). }
		RETURN TRUE.
	}
}

FUNCTION DownloadLib {
	PARAMETER fileName.
	RETURN DownloadFile(libsDir, fileName, TRUE, TRUE).
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

FUNCTION MissionUpdate {

	FUNCTION ProcessMission {
		IF EXISTS(missionDir + updateFile) { DELETEPATH(missionDir + updateFile). }
		MOVEPATH(downloadsDir + updateFile, missionDir + updateFile).
		DELETEPATH(downloadsDir + updateFile).
		Notify("Download complete! Running instructions...", 5, GREEN).
		WAIT 4.
		RunMission().
	}

	Notify("Downloading mission update.").
	IF DownloadFile(missionUpdateDir, updateFile) {
		ProcessMission().
	} ELSE IF DownloadFile(missionUpdateDir, altUpdateFile) {
		MOVEPATH(downloadsDir + altUpdateFile, downloadsDir + updateFile).
		ProcessMission().
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
	FOR f IN OPEN(systemUpdateDir) {
		IF f:NAME:STARTSWITH("probeOS_") AND f:NAME <> currentSystemVersion {
			IF f:NAME:SUBSTRING(8, f:NAME:LENGTH()-11):TONUMBER() > version {
				KUNIVERSE:TIMEWARP:CANCELWARP().
				WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED.
				SystemUpdate(f:NAME).
			}
		}
	}
	//	If no boot file update needed, check for mission updates
	IF EXISTS(missionUpdateDir + updateFile) OR EXISTS(missionUpdateDir + altUpdateFile) {	//	If no boot/config file update needed, check for mission updates
		KUNIVERSE:TIMEWARP:CANCELWARP().
		WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED.
		MissionUpdate().
	}
}

FUNCTION StandBy {
	IF hasSolars AND (VANG(SHIP:FACING:VECTOR, SUN:POSITION:NORMALIZED - solarsVector) > 1) OR (SHIP:ANGULARVEL:MAG > 0.01) {
		PrintValue("Facing Sun", 7, 25).
		SAS OFF.
		SET steeringLocked TO TRUE.
		IF RCSForRotation { RCS ON. }
		LOCK STEERING TO SUN:POSITION:NORMALIZED - solarsVector. // TODO: Test this to make sure it's correct
		WAIT UNTIL (VANG(SHIP:FACING:VECTOR, SUN:POSITION:NORMALIZED - solarsVector) < 0.1) AND (SHIP:ANGULARVEL:MAG < 0.001).
		WAIT 5.
		UNLOCK STEERING.
		SET steeringLocked TO FALSE.
		RCS OFF.
		SAS ON.
		WAIT 0.
		KUNIVERSE:TIMEWARP:WARPTO(TIME:SECONDS + 1).
		WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED.
		Notify("Facing the sun! Remember to set rotation relative to Sun in Persistant Rotation", 10, GREEN).
	}
	PrintValue("None", 7, 25).
}

FUNCTION AutoConfig {
	// TODO: Write the logic
	// Requirements:
	// * Check if ship has solar panels
	// * - if solar panels are present, check their orientation
	// * Check if ship has reaction wheels
	// *- if reaction wheels are present, check if they have enough torque to rotate ship
}

// Create the terminal UI
FUNCTION CreateUI {
	CLEARSCREEN.
	SET TERMINAL:WIDTH TO 53.

	PRINT ".---------------------------------------------------.".
	PRINT "| Not Available                                     |".
	PRINT "|---------------------------------------------------|".
	PRINT "| System version       - N/A                        |".
	PRINT "|---------------------------------------------------|".
	PRINT "| Configuration status - N/A                        |".
	PRINT "| Connection status    - N/A                        |".
	PRINT "| Active standby task  - N/A                        |".
	PRINT "|---------------------------------------------------|".
	PRINT "| Free Disk Space      - N/A                        |".
	PRINT "| Active Time          - 0s                         |".
	PRINT "'---------------------------------------------------'".
}

// Print a value to the terminal UI
FUNCTION PrintValue {
	PARAMETER val.      //  Message to write (string/scalar)
	PARAMETER line.     //  Line to write to (scalar)
	PARAMETER start.    //  First column to write to, inclusive (scalar)
	LOCAL len IS 51-start.
	LOCAL str IS val:TOSTRING().
	IF str:LENGTH>len { SET str TO str:SUBSTRING(0, len-2)+"..". }
	ELSE { SET str TO str:PADRIGHT(len). }
	PRINT str AT(start, line).
}

// Check for an on-going mission and let it complete.
IF missionInProgress {
	Notify("Resuming ongoing mission...", 4, GREEN).
	WAIT 4.
	RunMission().
}

IF configured { PrintValue("Auto-configured", 5, 25). }
ELSE { PrintValue("Not configured", 5, 25). }

Notify("System loaded successfully! Running ProbeOS v" + version + ".").

PrintValue(ROUND(VOLUME(1):FREESPACE,1) + "k/" + ROUND(VOLUME(1):CAPACITY,1) + "k " + ROUND(VOLUME(1):FREESPACE/VOLUME(1):CAPACITY*100,1) + "%", 9, 25).

UNTIL FALSE {
	IF HOMECONNECTION:ISCONNECTED {
		PrintValue("Connected", 6, 25).
		GetUpdates().
	} ELSE {
		PrintValue("Not connected", 6, 25).
		WAIT UNTIL HOMECONNECTION:ISCONNECTED.
	}
	IF KUNIVERSE:TIMEWARP:MODE = "RAILS" AND KUNIVERSE:TIMEWARP:RATE > 1 {
		WAIT KUNIVERSE:TIMEWARP:RATE.
	} ELSE {
		IF configured { StandBy(). }
		WAIT 10.
	}
	PrintValue(ROUND(TIME:SECONDS-bootTime) + "s", 10, 25).
}