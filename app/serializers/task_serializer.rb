class TaskSerializer < ContestTaskSerializer
  attributes :statement, :constraints, :input_format, :output_format, :samples
end
