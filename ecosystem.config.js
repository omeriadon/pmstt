module.exports = {
	apps: [
		{
			name: "timetable-api",
			script: ".build/release/pmstt",
			cwd: "/var/www/timetable",
			args: "serve --env production",
      interpreter: "none",
			env_production: {
				HOSTNAME: "127.0.0.1",
				PORT: "8081"

        APNS_TEAM_ID: "P6PV2R9443",
				APNS_KEY_ID: "LS45S5RDJ2",
        APNS_PRIVATE_KEY_PATH: "/etc/timetable/apns/AuthKey_KEYID.p8",
				APNS_BUNDLE_ID: "com.omeriadon.Timetable",
				APNS_USE_SANDBOX: "false"
			}
		}
	]
}

