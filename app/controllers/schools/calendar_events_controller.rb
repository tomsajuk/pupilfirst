module Schools
  class CalendarEventsController < SchoolsController
    layout "school"

    # GET /school/courses/:course_id/calendar_events/:id/show
    def show
      @course = current_school.courses.find(params[:course_id])
      @event = @course.calendar_events.find(params[:id])
      authorize(@event, policy_class: Schools::CalendarEventPolicy)
    end
    # GET /school/courses/:course_id/calendar_events/new
    def new
      @course = current_school.courses.find(params[:course_id])
      @event = CalendarEvent.new
      @form = CalendarEvents::CreateOrUpdateForm.new
      authorize(@event, policy_class: Schools::CalendarEventPolicy)
    end

    # GET /school/courses/:course_id/calendar_events/:id/edit
    def edit
      @course = current_school.courses.find(params[:course_id])
      @event = @course.calendar_events.find(params[:id])
      authorize(@event, policy_class: Schools::CalendarEventPolicy)
    end
    # POST /school/courses/:course_id/calendar_events/
    def create
      @course = current_school.courses.find(params[:course_id])
      authorize(CalendarEvent.new, policy_class: Schools::CalendarEventPolicy)

      @form =
        CalendarEvents::CreateOrUpdateForm.new(calendar_event_params(params))

      @form.validate

      if @form.valid?
        students = get_student_emails_of_course(@course)
        google_calender_id = GoogleCalenderService.new(current_user).create_event(calendar_event_params(params), students)
        @form.google_event_id = google_calender_id

        @form.save
        flash[:success] = I18n.t("calendar_events.create.success")
        redirect_to school_course_calendar_events_path(
                      @course,
                      calendar_id: params[:calendar_id]
                    )
      else
        flash.now[:error] = @form.errors.map { |e| e.full_message }
        @event = CalendarEvent.new
        render :new
      end
    end

    def update
      @event = current_school.calendar_events.find(params[:id])
      authorize(@event, policy_class: Schools::CalendarEventPolicy)

      @form =
        CalendarEvents::CreateOrUpdateForm.new(
          calendar_event_params(params).merge!(id: @event.id)
        )

      @form.validate

      if @form.valid?
        if (@event.google_event_id?)
          GoogleCalenderService.new(current_user).update_event(@event.google_event_id, calendar_event_params(params))
        end

        @form.save
        flash[:success] = I18n.t("calendar_events.update.success")
        redirect_to school_course_calendar_event_path(
                      @event.calendar.course,
                      @event,
                      calendar_id: params[:calendar_id]
                    )
      else
        flash.now[:error] = @form.errors.map { |e| e.full_message }
        render :edit
      end
    end

    def destroy
      @event = current_school.calendar_events.find(params[:id])
      authorize(@event, policy_class: Schools::CalendarEventPolicy)
      if @event.google_event_id?
        GoogleCalenderService.new(current_user).delete_event(@event.google_event_id)
      end
      @event.destroy

      flash[:success] = I18n.t("calendar_events.delete.success")
      redirect_to school_course_calendar_events_path(
                    @event.calendar.course,
                    calendar_id: params[:calendar_id]
                  )
    end

    private

    def calendar_event_params(params)
      params.require(:calendar_event).permit(
        :title,
        :description,
        :calendar_id,
        :color,
        :start_time,
        :end_time,
      )
    end

    def get_student_emails_of_course(course)
      user_ids = Student.joins(:course).where({ courses: { id: course.id }}).pluck(:user_id)
      User.where(id: user_ids).pluck(:email)
    end
  end
end
