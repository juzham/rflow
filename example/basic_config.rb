RFlow::Configuration::RubyDSL.configure do |config|
  # Configure the settings, which include paths for various files, log
  # levels, and component specific stuffs
  config.setting('rflow.log_level', 'DEBUG')
  config.setting('rflow.application_directory_path', '.')

  # Instantiate components
  config.component 'generate_ints', 'RFlow::Components::GenerateIntegerSequence', 'start' => 20, 'finish' => 30
  config.component 'output', 'RFlow::Components::FileOutput', 'output_file_path' => '/tmp/crap'
  config.component 'output_even', 'RFlow::Components::FileOutput', 'output_file_path' => '/tmp/crap_even'
  config.component 'output_odd', 'RFlow::Components::FileOutput', 'output_file_path' => '/tmp/crap_odd'

  # Hook components together
  config.connect 'generate_ints#even_odd_out' => 'output#in'
  config.connect 'generate_ints#even_odd_out[even]' => 'output_even#in'
  config.connect 'generate_ints#even_odd_out[odd]' => 'output_odd#in'


end


