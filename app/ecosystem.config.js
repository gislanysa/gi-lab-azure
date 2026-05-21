module.exports = {
  apps: [
    {
      name: 'marcozero-api',
      script: 'server.js',
      instances: 2,
      exec_mode: 'cluster',
      max_memory_restart: '300M',
      autorestart: true,
      env: {
        NODE_ENV: 'production',
      },
      out_file:   './logs/out.log',
      error_file: './logs/error.log',
      merge_logs: true,
      time: true,
    },
  ],
};
