class Api::SubmitsController < ApplicationController

  # pathを生やす
  def make_path
    return Rails.root.join("submit_sources", SecureRandom.uuid)
  end

  def show
    contest_slug = params[:contest_slug]
    user_id = 1
    # :contest_slugからsubmitを抽出する
    render json: Submit.joins(problem: :contest)
                  .select("submits.*, problems.id, problems.contest_id, contests.id, contests.slug")
                  .where("contests.slug = ? and user_id = ?", contest_slug, user_id)
    
  end

  def create
    @problem = Problem.find_by!(slug: params[:task_slug])
    save_path = make_path

    # ちゃんとバリデーションした方が良さそう？
    @submit = Submit.new
    @submit.user_id = 1
    @submit.problem_id = @problem.id
    @submit.path = save_path
    @submit.lang = request.headers[:lang]
    @submit.status = request.headers[:status]
    @submit.execution_time = 1.0
    @submit.execution_memory = 256
    @submit.point = 114514

    @submit.save

    submited_code = request.body.read

    File.open(save_path, 'w') do |fp|
      fp.puts submited_code
    end

    redirect_to action: :show, contest_slug: params[:contest_slug]

  end


end
