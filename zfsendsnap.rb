SLACK = {
  webhook_url: ''
  username: 'ZFS replica',
  channel: '#luna',
}

DATASET_MAP = {
  'zroot/home' => {
    dst: {
      server: 'mike',
      port: 3010,
      dataset: 'zbak/luna',
    },
    prefix: 'prefix-'
  },
}
