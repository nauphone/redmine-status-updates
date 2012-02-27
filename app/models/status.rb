class Status < ActiveRecord::Base
  belongs_to :project
  belongs_to :user

  validates_presence_of :project_id
  extend StatusesHelper
  
  attr_protected :project_id

  acts_as_activity_provider :type => 'statuses', :find_options => {:include => [:project, :user]},
                            :author_key => :user_id

  Hashtag = /(#\S+)/

  named_scope :for_project, lambda {|project|
    {
      :conditions => {:project_id => project.id}
    }
  }
  
  named_scope :recent, lambda {|number|
    {
      :limit => number
    }
  }

  named_scope :by_date, lambda {
    {
      :order => "created_at DESC"
    }
  }

  named_scope :tagged_with, lambda {|tag|
    {
      :conditions => ["message LIKE (?)", "%#" + tag.to_s + "%"]
    }
  }

  named_scope :with_message_containing, lambda {|term|
    {
      :conditions => ["message LIKE (?)", "%" + term.to_s + "%"]
    }
  }

  named_scope :since, lambda {|date|
    {
      :conditions => ["created_at >= ?", date]
    }
  }

  named_scope :visible_to_user, lambda {|user, project|
    {
      :conditions => Project.allowed_to_condition(user, :view_statuses, {:project => project}),
      :include => :project
    }
  }
  
  def has_hashtag?
    return (message && message.match(Hashtag)) ? true : false
  end

  # Realtime recipients who should be notified
  def recipients
    return [] if self.project.blank?
    returning [] do |recipients|
      self.project.members.collect(&:user).each do |user|
        recipients << user.mail if user.realtime_status_notification? && user.mail
      end
    end
  end

  def self.recent_updates_for(project=nil, number=100)
    if project
      return self.visible_to_user(User.current, project).recent(number).by_date.for_project(project)
    else
      return self.visible_to_user(User.current, project).recent(number).by_date
    end
  end
  
  def self.recently_tagged_with(tag, project=nil)
    if project
      return self.visible_to_user(User.current, project).recent(100).by_date.for_project(project).tagged_with(tag)
    else
      return self.visible_to_user(User.current, project).recent(100).by_date.tagged_with(tag)
    end
  end

  def self.search(term, project=nil)
    if project
      return self.visible_to_user(User.current, project).recent(100).by_date.for_project(project).with_message_containing(term)
    else
      return self.visible_to_user(User.current, project).recent(100).by_date.with_message_containing(term)
    end
  end

  # Returns the data for a tag cloud
  #
  # {:name => :count}
  def self.tag_cloud(project = nil)
    tagged_statuses = Status.visible_to_user(User.current, project).tagged_with('')
    cloud = {}
    tagged_statuses.each do |status|
      tags = status.message.scan(/#\S*/)
      tags.each do |tag|
        tag = remove_non_tag_characters(tag)
        cloud[tag.downcase] ||= 0
        cloud[tag.downcase] += 1
      end
    end

    cloud
  end

  # Activity methods

  def event_datetime
    self.created_at.to_time
  end

  def event_date
    self.created_on
  end

  def event_type
    'status'
  end

  def event_title
    I18n.t 'activity_user_updated_his_status', {
      :user_name => self.user.name,
      :project_name => self.project.name
    }
  end

  def event_url
    { :controller => 'statuses', :action => 'index', :id => self.project }
  end

  def event_description
    self.message
  end
end
