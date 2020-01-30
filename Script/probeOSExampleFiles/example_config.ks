LOCAL command_disableSystems IS  {
	LOCAL m IS SHIP:PARTSDUBBED("longAntenna")[0]:GETMODULE("ModuleRTAntenna").
	IF m:HASEVENT("deactivate") {
		m:DOEVENT("deactivate").
		NOTIFY("Disabling systems to preserve power!", 10, RED).
	}
}.
LOCAL command_enableSystems IS {
	LOCAL m IS SHIP:PARTSDUBBED("longAntenna")[0]:GETMODULE("ModuleRTAntenna").
	IF m:HASEVENT("activate") {
		m:DOEVENT("activate").
		NOTIFY("Enabling systems again!", 10, GREEN).
	}
}.
SET vehicle TO LEXICON(
	"on-low-power", LEXICON(
		"disable-systems", command_disableSystems@,
		"enable-systems", command_enableSystems@
		)
	).