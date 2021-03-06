class Api::SubmitsController < ApplicationController
  include Pagination
  before_action :authenticate_user!, except: [:all, :show]

  def index
    if current_user.nil?
      render status: :unauthorized
      return
    end
    contest_slug = params[:contest_slug]
    user_id = current_user.id
    page = params[:page] || 1
    count = params[:count] || 20

    submissions(
      Submit.includes(problem: :testcase_sets)
            .includes(:testcase_results)
            .eager_load(:user)
            .joins(problem: :contest)
            .where("contests.slug = ?", contest_slug)
            .search_by_user_id(user_id)
            .page(page)
            .per(count),
      Contest.find_by!(slug: contest_slug).problems.pluck(:id),
      params[:options]
    )
  end

  def all
    contest_slug = params[:contest_slug]
    # @type [Contest]
    contest = Contest.find_by!(slug: contest_slug)
    page = params[:page] || 1
    count = params[:count] || 20

    unless contest.end_at.past?
      unless user_signed_in? && contest.is_writer_or_tester(current_user)
        render_403
        return
      end
    end

    submissions(
      Submit.includes(problem: :testcase_sets)
            .includes(:testcase_results)
            .eager_load(:user)
            .joins(problem: :contest)
            .where("contests.slug = ?", contest_slug)
            .page(page)
            .per(count),
      contest.problems.pluck(:id),
      params[:options]
    )
  end

  def show
    #@type [Submit]
    submit = Submit.includes(testcase_results: :testcase).find(params[:id])
    contest = submit.problem.contest

    if contest.slug != params[:contest_slug]
      render status: :not_found
      return
    end

    is_admin_or_writer = user_signed_in? && (
      current_user.admin? ||
      submit.problem.writer_user_id == current_user.id ||
      submit.problem.tester_relations.where(tester_user_id: current_user.id, approved: true).exists? ||
      contest.is_writer_or_tester(current_user) && contest.official_mode
    )

    if !user_signed_in? || (!is_admin_or_writer && submit.user_id != current_user.id)
      unless contest.end_at.past?
        render json: {
            error: 'この提出は非公開です'
        }, status: :forbidden
        return
      end
    end

    samples = submit
                  .problem
                  .testcase_sets
                  .where(is_sample: 1)
                  .joins(:testcases)
                  .pluck(:testcase_id)

    in_contest = contest.end_at.future? && !is_admin_or_writer
    r_count = submit.testcase_results.count
    t_count = submit.problem.testcases
                  .where('created_at < ?', submit.updated_at)
                  .count

    require('set')
    render json: submit,
           serializer: SubmitDetailSerializer,
           in_contest: in_contest,
           hide_results: r_count < t_count,
           samples: in_contest ? Set.new(samples) : nil,
           result_count: r_count,
           testcase_count: t_count
  end

  def create
    if current_user.nil?
      render status: :unauthorized
      return
    end

    problem = Problem.find_by!(slug: params[:task_slug])
    _submit(problem, request.body.read)
  end

  private
    
  # @param submissions [ActiveRecord::Relation<Submit>]
  def submissions(submissions, problem_ids, options)
    sort_table = {
      'date' => %w[created_at],
      'user' => %w[users.name],
      'lang' => %w[lang],
      'score' => %w[point],
      'status' => %w[status],
      'executionTime' => %w[execution_time],
      'executionMemory' => %w[execution_memory],
    }
    filter_table = {
      'user' => 'users.name',
      'task' => 'problems.slug',
      'status' => 'status',
    }
    if options.present?
      options_data = JSON.parse(options)
      sort_array = options_data['sort'] || []
      sort_array.each do |obj|
        if obj['target'] == 'task'
          desc = obj['desc'] ? 'DESC' : 'ASC'
          submissions.order!("CHAR_LENGTH(problems.position) #{desc}").order!(position: desc)
        else
          sort_table[obj['target']].each { |row| submissions.order!(row => obj['desc'] ? :desc : :asc) }
        end
      end
      filter_array = options_data['filter'] || []
      filter_array.each do |obj|
        submissions.where!(filter_table[obj['target']] => obj['value'])
      end
    end

    all_testcases = get_testcases(problem_ids)
    submissions = submissions.order(created_at: :desc)
    pagination_data = pagination(submissions)

    data = submissions.map do |submission|
      # @type [Array<ActiveSupport::TimeWithZone>]
      c_testcases = all_testcases[submission.problem_id]&.map { |x| x.created_at }

      if c_testcases.nil?
        testcase_count = 0
      else
        idx = c_testcases.bsearch_index { |t| t > submission.updated_at }
        testcase_count = idx.nil? ? c_testcases.length : idx
      end

      SubmitSerializer::new(submission, result_count: submission.testcase_results.count, testcase_count: testcase_count)
    end

    render json: { data: data, meta: pagination_data }
  end

  def _submit(problem, source)
    unless problem.has_permission?(current_user)
      render_403
    end

    save_path = make_path

    submit = current_user.submits.new
    submit.problem_id = problem.id
    submit.path = save_path
    submit.lang = request.headers[:lang]
    submit.status = 'WJ'

    Utils::GoogleCloudStorageClient::upload_source(save_path, source)
    submit.save!
  end

  def get_testcases(problem_ids)
    Testcase.where(problem_id: problem_ids)
        .select(:problem_id, :created_at)
        .order(:created_at)
        .to_a
        .group_by { |t| t.problem_id }
  end

  # pathを生やす
  def make_path
    "submit_sources/#{SecureRandom.uuid}"
  end
end
