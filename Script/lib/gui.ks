// Display a gui and get mission details from user.
// This is only meant to be used with PEGAS to create it's mission structure.
FUNCTION CreateMissionGUI {
	// Create a gui window
	LOCAL gui IS GUI(400).

	// Add widgets to the GUI
	// Payload Mass
	LOCAL payloadMass IS 0.
	IF DEFINED launchVehicleMass { SET payloadMass TO SHIP:MASS - launchVehicleMass. }
	LOCAL labelPayloadMass IS gui:ADDLABEL("Payload Mass [kg]<b><color=#ff0000ff></color>*</b>").
	SET labelPayloadMass:STYLE:ALIGN TO "CENTER".
	SET labelPayloadMass:STYLE:HSTRETCH TO TRUE. // Fill horizontaly
	LOCAL textPayloadMass IS gui:ADDTEXTFIELD(payloadMass:TOSTRING).
	SET textPayloadMass:STYLE:ALIGN TO "CENTER".
	SET textPayloadMass:STYLE:HSTRETCH TO TRUE.
	SET textPayloadMass:TOOLTIP TO "Enter if not filled in automatically".

	// Target Apoapsis
	LOCAL labelApoapsis IS gui:ADDLABEL("Target Apoapsis [km]").
	SET labelApoapsis:STYLE:ALIGN TO "CENTER".
	SET labelApoapsis:STYLE:HSTRETCH TO TRUE. // Fill horizontaly
	LOCAL textApoapsis IS gui:ADDTEXTFIELD(250:TOSTRING).
	SET textApoapsis:STYLE:ALIGN TO "CENTER".
	SET textApoapsis:STYLE:HSTRETCH TO TRUE.
	SET textApoapsis:TOOLTIP TO "Minimum 150km".

	// Target Periapsis
	LOCAL labelPeriapsis IS gui:ADDLABEL("Target Periapsis [km]").
	SET labelPeriapsis:STYLE:ALIGN TO "CENTER".
	SET labelPeriapsis:STYLE:HSTRETCH TO TRUE. // Fill horizontaly
	LOCAL textPeriapsis IS gui:ADDTEXTFIELD(250:TOSTRING).
	SET textPeriapsis:STYLE:ALIGN TO "CENTER".
	SET textPeriapsis:STYLE:HSTRETCH TO TRUE.
	SET textPeriapsis:TOOLTIP TO "Minimum 150km".

	// Target Inclination
	LOCAL labelInclination IS gui:ADDLABEL("Target Inclination [deg]").
	SET labelInclination:STYLE:ALIGN TO "CENTER".
	SET labelInclination:STYLE:HSTRETCH TO TRUE. // Fill horizontaly
	LOCAL textInclination IS gui:ADDTEXTFIELD(ABS(SHIP:LATITUDE):TOSTRING).
	SET textInclination:STYLE:ALIGN TO "CENTER".
	SET textInclination:STYLE:HSTRETCH TO TRUE.
	SET textInclination:TOOLTIP TO "Between 0 and 180".

	// Target LAN
	LOCAL labelLAN IS gui:ADDLABEL("Target LAN [deg]").
	SET labelLAN:STYLE:ALIGN TO "CENTER".
	SET labelLAN:STYLE:HSTRETCH TO TRUE. // Fill horizontaly
	LOCAL textLAN IS gui:ADDTEXTFIELD().
	SET textLAN:STYLE:ALIGN TO "CENTER".
	SET textLAN:STYLE:HSTRETCH TO TRUE.
	SET textLAN:TOOLTIP TO "Between 0 and 360".

	// Testing
	LOCAL labelGs IS gui:ADDLABEL("Launch g limit [g]").
	SET labelGs:STYLE:ALIGN TO "CENTER".
	SET labelGs:STYLE:HSTRETCH TO TRUE. // Fill horizontaly
	LOCAL valHLayout IS gui:ADDHLAYOUT().
	LOCAL checkGs IS valHLayout:ADDCHECKBOX("Enabled", TRUE).
	LOCAL sliderGs IS valHLayout:ADDHSLIDER(3,1.5,6).
	SET sliderGs:STYLE:HSTRETCH TO TRUE. // Fill horizontaly
	LOCAL textGs IS valHLayout:ADDTEXTFIELD(ROUND(sliderGs:VALUE,1):TOSTRING).
	SET textGs:STYLE:ALIGN TO "CENTER".
	SET textGs:STYLE:WIDTH TO 50.
	SET textGs:ENABLED TO FALSE.

	SET sliderGs:ONCHANGE TO {
		PARAMETER newValue.
		SET textGs:TEXT TO ROUND(newValue,1):TOSTRING.
	}.

	SET checkGs:ONTOGGLE TO {
		PARAMETER newState.
		SET sliderGs:ENABLED TO newState.
		IF newState {
			SET textGs:TEXT TO ROUND(sliderGs:VALUE,1):TOSTRING.
		} ELSE {
			SET textGs:TEXT TO 0:TOSTRING.
		}
	}.

	LOCAL buttonLaunch TO gui:ADDBUTTON("Launch!").
	LOCAL buttonAbort TO gui:ADDBUTTON("Abort").
	// Show the GUI
	gui:SHOW().

	LOCAL isDone IS FALSE.
	UNTIL isDone {
		IF buttonLaunch:TAKEPRESS {
			// Do stuff...
			SET isDone TO TRUE.
		} ELSE IF buttonAbort:TAKEPRESS {
			// Do stuff...
			RETURN FALSE.
		}
		WAIT 0.1.
	}
	gui:HIDE().
	CLEARGUIS().
	RETURN TRUE.
}