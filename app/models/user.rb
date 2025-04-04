class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
        # , :confirmable

  validates :email, presence: true
  validates :name, presence: true
  validates :name_kana, presence: true, on: :update
  validates_format_of :name_kana, with: /\A[ぁ-んー－]+\z/, message: "は平仮名で入力してください", on: :update
  validates :tel, presence: true, on: :update
  validates :tel, numericality: true, on: :update
  validates :birthday, presence: true, on: :update
  # validates :introducer, presence: true, on: :update
  validates :gender, presence: true, on: :update
  
  has_many :reservations, :dependent => :destroy
  has_many :reserves, :dependent => :destroy
  has_many :payments, :dependent => :destroy
  has_many :schedules, :dependent => :destroy
  has_one :staff, :dependent => :destroy
  
  
  def self.search(search) #self.でクラスメソッドとしている
    logger.debug("~~~~~~~~~~~~~~~~~~~~~~~search  => #{search}")

    if !search.nil?
        logger.debug("~~~~~~~~~~~~~~~~~~~~~~~search  !=> nil")
      if search[:user_type] != ""
        logger.debug("~~~~~~~~~~~~~~~~~~~~~~~user_type !=> nil")
        if search[:name].present? || search[:user_type].present?
          User.where(User.arel_table[:name].matches("%#{search[:name]}%")).where(User.arel_table[:user_type].matches(search[:user_type]))
        else
          User.all #全て表示。
        end
      else
        logger.debug("~~~~~~~~~~~~~~~~~~~~~~~user_type = blank")
        User.where(User.arel_table[:name].matches("%#{search[:name]}%"))
      end
    else
        User.all #全て表示。
    end
  end
  
  def new_customer?
    if self.user_type == "11"
      return true
    else
      return false
    end
  end
  
  def new_customer_display
    if self.user_type == "11"
      return "新規"
    else
      return "既存"
    end
  end

end
