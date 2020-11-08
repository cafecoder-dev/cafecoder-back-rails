class Api::ProblemsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_writer!

  # GET /problems
  def index
    problems = Problem.includes(:writer_user, :contest).order(id: :desc)
    problems.where!(writer_user_id: current_user.id) unless current_user.admin?

    render json: problems
  end

  # GET /problems/1
  def show
    problem = Problem.includes(:testers).find(params[:id])
    if !current_user.admin? &&
        problem.writer_user_id != current_user.id &&
        problem.tester_relations.where(tester_user_id: current_user.id, approved: true).empty?
      render_403
      return
    end
    render json: problem, serializer: ProblemDetailSerializer
  end

  # POST /problems
  def create
    ActiveRecord::Base.transaction do
      @problem = Problem.new(problem_params)
      @problem.uuid = SecureRandom.uuid
      @problem.writer_user_id = current_user.id

      if @problem.save
        @problem.testcase_sets.create(
            name: 'sample',
            points: 0,
            is_sample: true
        )
        @problem.testcase_sets.create(
            name: 'all',
            points: 100,
            is_sample: false
        )

        render serializer: ProblemDetailSerializer, status: :created
      else
        render json: @problem.errors, status: :unprocessable_entity
      end
    end
  end

  # PATCH/PUT /problems/1
  def update
    problem = Problem.find(params[:id])
    unless current_user.admin? || problem.writer_user_id == current_user.id
      render_403
      return
    end

    if problem.update(problem_params)
      render serializer: ProblemDetailSerializer
    else
      render json: problem.errors, status: :unprocessable_entity
    end
  end

  private

  # Only allow a trusted parameter "white list" through.
  def problem_params
    params.require(:problem).permit(:name, :difficulty, :statement, :constraints, :input_format, :output_format)
  end

  def authenticate_writer!
    unless current_user.admin? || current_user.writer?
      render_403
    end
  end
end
