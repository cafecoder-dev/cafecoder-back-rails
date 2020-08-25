class SubmitSerializer < ActiveModel::Serializer
  attributes :id, :user, :task, :status, :point,
             :execution_time, :execution_memory, :lang, :timestamp, :judge_status

  def user
    {
        name: object.user.name
    }
  end

  def task
    ContestTaskSerializer::new(
        object.problem
    )
  end

  def timestamp
    object.created_at
  end

  def judge_status
    completed = @instance_options[:result_counts][object.id] || 0
    all = @instance_options[:testcase_count][object.problem.id]
    if completed >= all || completed == 0
      nil
    else
      {completed: completed, all: all}
    end
  end
end
