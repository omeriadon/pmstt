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
			}
		}
	]
}

