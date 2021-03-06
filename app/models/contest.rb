class Contest < ApplicationRecord
  include ActiveModel::Serialization
  include ActiveModel::Model

  has_many :problems, -> { order('char_length(`position`)').order(:position) }
  has_many :clarifications
  has_many :registrations

  def to_param
    slug
  end

  # @param [User] user
  def registered?(user)
    user.present? && (user.admin? || self.registrations.exists?(user_id: user.id))
  end

  def is_writer_or_tester(user)
    return false if user.nil?

    return true if user.admin?

    self.problems.exists?(writer_user_id: user.id) ||
      TesterRelation.exists?(problem: self.problems, tester_user_id: user.id)
  end
end
