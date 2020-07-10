require 'spec_helper'
require 'helm_template_helper'
require 'yaml'

describe 'Database configuration' do
  let(:default_values) do
    {
      'certmanager-issuer' => { 'email' => 'test@example.com' },
      'global' => {
        'psql' => {
          'host' => '',
          'serviceName' => '',
          'port' => nil,
          'pool' => '',
          'username' => '',
          'database' => '',
          'preparedStatements' => '',
          'password' => { 'secret' => '', 'key' => '' },
          'load_balancing' => {}
        }
      },
      'postgresql' => { 'install' => true }
    }
  end

  describe 'global.psql.load_balancing' do
    context 'when PostgreSQL is installed' do
      let(:values) do
        # merging in this order, so the local overrides win.
        default_values.merge({
          'global' => {
            'psql' => {
              'host' => 'primary',
              'load_balancing' => {
                'hosts' => [ 'secondary-1', 'secondary-2']
              }
            }
          },
        })
      end

      it 'fail due to checkConfig' do
        t = HelmTemplate.new(values)
        expect(t.exit_code).not_to eq(0)
        expect(t.stderr).to include("PostgreSQL is set to install, but database load balancing is also enabled.")
      end
    end

    describe 'global.psql.load_balancing.hosts' do
      let(:values) do
        default_values.merge({
          'global' => {
            'psql' => {
              'host' => 'primary',
              'load_balancing' => {
                'hosts' => [ 'secondary-1', 'secondary-2']
              }
            }
          },
          'postgresql' => { 'install' => false }
        })
      end

      context 'when configured' do
        it 'populate configuration with load_balancing.hosts array' do
          t = HelmTemplate.new(values)
          expect(t.exit_code).to eq(0)
          expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include("host: \"primary\"")
          expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include("load_balancing:")
          expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include("hosts:")
          expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include("- secondary-1")
        end
      end   
    end

    describe 'global.psql.load_balancing.discover' do
      let(:values) do
        default_values.merge({
          'global' => {
            'psql' => {
              'host' => 'primary',
              'load_balancing' => {
                'discover' => {
                  # this is the only required setting
                  'record' => 'secondary.db.service'
                }
              }
            }
          },
          'postgresql' => { 'install' => false }
        })
      end

      context 'when configured' do
        it 'populate configuration wtih load_balancing.discover.record' do
          t = HelmTemplate.new(values)
          expect(t.exit_code).to eq(0)
          expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include("host: \"primary\"")
          expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include("load_balancing:")
          expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include("discover:")
          expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include("record: \"secondary.db.service\"")
        end
      end
    end
  end

  describe 'When using per chart configuration' do
    context 'when separate configuration is provided for Sidekiq' do
      let(:values) do
        # merging in this order, so the local overrides win.
        default_values.merge({
          'global' => {
            'psql' => {
              'host' => 'psql.global',
            },
          },
          'gitlab' => {
            'sidekiq' => {
              'psql' => {
                'host' => 'psql.other',
                'port' => 5431,
                'database' => 'sidekiq',
                'username' => 'sidekiq',
                'pool' => 5,
                'preparedStatements' => true
              },
            },
          },
        })
      end

      it 'configure webservice with "global", sidekiq with "other"' do
        t = HelmTemplate.new(values)
        expect(t.exit_code).to eq(0)
        # webservice gets "global"
        expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('host: "psql.global"')
        # sidekiq gets "other", with non-defaults
        expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('host: "psql.other"')
        expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('port: 5431')
        expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('database: sidekiq')
        expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('username: sidekiq')
        expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('pool: 5')
        expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('prepared_statements: true')
      end
    end

    context 'when separate configuration is provided for Webservice' do
      let(:values) do
        # merging in this order, so the local overrides win.
        default_values.merge({
          'global' => {
            'psql' => {
              'host' => 'psql.global',
            },
          },
          'gitlab' => {
            'webservice' => {
              'psql' => {
                'host' => 'psql.other',
                'port' => 5431,
                'database' => 'webservice',
                'username' => 'webservice',
                'pool' => 5,
                'preparedStatements' => true,
                'password' => {
                  'secret' => 'other-postgresql-password',
                  'key' => 'other-password',
                },
              },
            },
          },
        })
      end

      it 'configure sidekiq with "global", webservice with "other"' do
        t = HelmTemplate.new(values)
        expect(t.exit_code).to eq(0)
        # sidekiq gets "global"
        expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('host: "psql.global"')
        sidekiq_secret_mounts =  t.projected_volume_sources('Deployment/test-sidekiq-all-in-1-v1','init-sidekiq-secrets').select { |item|
          item['secret']['name'] == 'test-postgresql-password'
        }
        expect(sidekiq_secret_mounts.length).to eq(1)
        # webservice gets "other", with non-defaults
        expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('host: "psql.other"')
        expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('port: 5431')
        expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('database: webservice')
        expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('username: webservice')
        expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('pool: 5')
        expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('prepared_statements: true')
        webservice_secret_mounts =  t.projected_volume_sources('Deployment/test-webservice','init-webservice-secrets').select { |item|
          item['secret']['name'] == 'other-postgresql-password' && item['secret']['items'][0]['key'] == 'other-password'
        }
        expect(webservice_secret_mounts.length).to eq(1)
      end
    end

    context 'when overriding only host for Webservice' do
      let(:values) do
        # merging in this order, so the local overrides win.
        default_values.merge({
          'global' => {
            'psql' => {
              'host' => 'psql.global',
            },
          },
          'gitlab' => {
            'webservice' => {
              'psql' => {
                'host' => 'psql.other',
              },
            },
          },
        })
      end

      it 'only host is overridden' do
        t = HelmTemplate.new(values)
        expect(t.exit_code).to eq(0)
        # sidekiq gets "global"
        expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('host: "psql.global"')
        expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('port: 5432')
        expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('database: gitlabhq_production')
        expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('username: gitlab')
        expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('pool: 10')
        expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('prepared_statements: false')
        sidekiq_secret_mounts =  t.projected_volume_sources('Deployment/test-sidekiq-all-in-1-v1','init-sidekiq-secrets').select { |item|
          item['secret']['name'] == 'test-postgresql-password' && item['secret']['items'][0]['key'] == 'postgresql-password'
        }
        expect(sidekiq_secret_mounts.length).to eq(1)
        # webservice gets "other", with non-defaults
        expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('host: "psql.other"')
        expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('port: 5432')
        expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('database: gitlabhq_production')
        expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('username: gitlab')
        expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('pool: 10')
        expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('prepared_statements: false')
        webservice_secret_mounts =  t.projected_volume_sources('Deployment/test-webservice','init-webservice-secrets').select { |item|
          item['secret']['name'] == 'test-postgresql-password' && item['secret']['items'][0]['key'] == 'postgresql-password'
        }
        expect(webservice_secret_mounts.length).to eq(1)
      end
    end

    context 'when setting global password, it is inherited when not overridden' do
      let(:values) do
        # merging in this order, so the local overrides win.
        default_values.merge({
          'global' => {
            'psql' => {
              'host' => 'psql.global',
              'password' => {
                'secret' => 'global-postgresql-password',
                'key' => 'global-password'
              }
            },
          },
          'gitlab' => {
            'webservice' => {
              'psql' => {
                'host' => 'psql.other',
              },
            },
          },
        })
      end

      it 'password is inherited, if not specified' do
        t = HelmTemplate.new(values)
        expect(t.exit_code).to eq(0)
        # sidekiq gets "global"
        expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('host: "psql.global"')
        sidekiq_secret_mounts =  t.projected_volume_sources('Deployment/test-sidekiq-all-in-1-v1','init-sidekiq-secrets').select { |item|
          item['secret']['name'] == 'global-postgresql-password' && item['secret']['items'][0]['key'] == 'global-password'
        }
        expect(sidekiq_secret_mounts.length).to eq(1)
        # webservice gets "other", with non-defaults
        expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('host: "psql.other"')
        webservice_secret_mounts =  t.projected_volume_sources('Deployment/test-webservice','init-webservice-secrets').select { |item|
          item['secret']['name'] == 'global-postgresql-password' && item['secret']['items'][0]['key'] == 'global-password'
        }
        expect(webservice_secret_mounts.length).to eq(1)
      end
    end

    describe 'when load_balancing is used' do
      context 'load_balancing is configured globally, not by Webservice' do
        let(:values) do
          # merging in this order, so the local overrides win.
          default_values.merge({
            'postgresql'=> {
              'install' => false
            },
            'global' => {
              'psql' => {
                'host' => 'global.primary',
                'load_balancing' => {
                  'hosts' => [ 'global.secondary-1', 'global.secondary-2']
                }
              },
            },
            'gitlab' => {
              'webservice' => {
                'psql' => {
                  'host' => 'psql.other',
                },
              },
            },
          })
        end

        it 'load_balancing is not inherited by Webservice, but used by Sidekiq' do
          t = HelmTemplate.new(values)
          expect(t.exit_code).to eq(0)
          # sidekiq gets "global"
          expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('host: "global.primary"')
          expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('load_balancing:')
          expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('hosts:')
          expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('- global.secondary-1')
          # webservice gets "other", with non-defaults
          expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('host: "psql.other"')
          expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).not_to include("load_balancing:")
        end
      end

      context 'load_balancing is configured globally, and for Webservice' do
        let(:values) do
          # merging in this order, so the local overrides win.
          default_values.merge({
            'postgresql'=> {
              'install' => false
            },
            'global' => {
              'psql' => {
                'host' => 'global.primary',
                'load_balancing' => {
                  'hosts' => [ 'global.secondary-1']
                }
              },
            },
            'gitlab' => {
              'webservice' => {
                'psql' => {
                  'host' => 'webservice.primary',
                  'load_balancing' => {
                    'hosts' => [ 'webservice.secondary-1']
                  }
                },
              },
            },
          })
        end

        it 'separate load_balancing is used by Webservice and Sidekiq' do
          t = HelmTemplate.new(values)
          expect(t.exit_code).to eq(0)
          # sidekiq gets "global"
          expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('host: "global.primary"')
          expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('load_balancing:')
          expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('hosts:')
          expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('- global.secondary-1')
          # webservice gets "other", with non-defaults
          expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('host: "webservice.primary"')
          expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('load_balancing:')
          expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('hosts:')
          expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('- webservice.secondary-1')
        end
      end

      context 'load_balancing is configured only for Webservice' do
        let(:values) do
          # merging in this order, so the local overrides win.
          default_values.merge({
            'postgresql'=> {
              'install' => false
            },
            'global' => {
              'psql' => {
                'host' => 'psql.global',
              },
            },
            'gitlab' => {
              'webservice' => {
                'psql' => {
                  'host' => 'webservice.primary',
                  'load_balancing' => {
                    'hosts' => [ 'webservice.secondary-1']
                  }
                },
              },
            },
          })
        end

        it 'load_balancing is only used by Webservice' do
          t = HelmTemplate.new(values)
          expect(t.exit_code).to eq(0)
          # sidekiq gets "global"
          expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).to include('host: "psql.global"')
          expect(t.dig('ConfigMap/test-sidekiq','data','database.yml.erb')).not_to include('load_balancing:')
          # webservice gets "other", with non-defaults
          expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('host: "webservice.primary"')
          expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('load_balancing:')
          expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('hosts:')
          expect(t.dig('ConfigMap/test-webservice','data','database.yml.erb')).to include('- webservice.secondary-1')
        end
      end
    end
  end
end