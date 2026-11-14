# Never log personal fields, uploaded files, passwords, or login identifiers.
Rails.application.config.filter_parameters += [/.*/]
