module Startups
  class TeamUpService
    def initialize(founders)
      @founders = founders
    end

    def team_up(name)
      raise "Students must belong to the same level for teaming up" unless @founders.joins(startup: :level).distinct('levels.id').pluck('levels.id').one?

      Startup.transaction do
        startup = Startup.create!(
          name: name,
          level: @founders.first.startup.level
        )

        # the new team formed should have all team coaches assigned for the current teams
        if old_startup_faculty.present?
          old_startup_faculty.each do |faculty|
            FacultyStartupEnrollment.create!(startup: startup, faculty: faculty, safe_to_create: true)
          end
        end

        old_startup_ids = @founders.pluck(:startup_id)

        @founders.update(startup: startup)

        # Clean up old startups if they're empty.
        # TODO: There is an assumption here that startups without founders can be safely destroyed.
        # TODO: Nothing (except founders) should depend on a startup.
        Startup.where(id: old_startup_ids).each do |old_startup|
          old_startup.destroy! if old_startup.founders.count.zero?
        end

        startup
      end
    end

    private

    def old_startup_faculty
      old_startup_ids = @founders.pluck(:startup_id)
      current_faculty_enrollments = FacultyStartupEnrollment.where(startup_id: old_startup_ids)
      if current_faculty_enrollments.exists?
        Faculty.where(id: current_faculty_enrollments.pluck(:faculty_id).uniq)
      end
    end
  end
end
