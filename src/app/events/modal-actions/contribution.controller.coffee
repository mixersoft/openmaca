###
# @description  EventContributionCtrl, controller for event booking modal form
###

EventContributionCtrl = (
  $scope, $rootScope, $q
  AAAHelpers
  $log, toastr
  ) ->
    mm = this
    # mm = {
    #   person: person
    #   event: event
    #   booking:
    #     userId: person.id
    #     seats: options['defaultSeats']
    #     comment: null
    # }
    #
    mm.afterModalShow = ()->
      # params from appModalSvc.show( template , controllerAs , params, options) available
      # add to mm
      angular.extend mm, angular.copy($scope.copyToModalViewModal), {
        isAnonymous: AAAHelpers.isAnonymous
        confirmEventId: $scope.vm.event.id
        confirmCurrentUserId: $scope.vm.me.id
      }

    mm.isValidated = (booking)->
      return false if AAAHelpers.isAnonymous()
      return false if booking?.seats < 1
      return true

    mm.createParticipation = (person, event, booking, participantIds)->
      # add booking as participant to event
      # clean up data
      particip = {
        eventId: event.id
        participantId: person.id + ''
        response: 'Yes'
        seats: parseInt booking.seats
        comment: booking.comment
      }
      # check for existing participation
      if ~participantIds?.indexOf(person.id)
        return $q.reject("DUPLICATE KEY")

      # booking by definition is a new response
      maxSeats =
        if event.settings['denyRsvpFriends']
        then 1
        else event.settings['rsvpFriendsLimit']
      return $q.reject('RSVP FRIENDS LIMIT') if particip['seats'] > maxSeats

      return $q.when(particip)

    mm.on = {
      signInRegister : (action, person)->
        # update booking user after sign in/register
        return self.showSignIn.call($scope.vm, action)
        .then (result)->
          _.extend person, result
          return

      searchTiles : (value, set)->
        # return $scope.vm.on?searchTiles(value)
        mm.autocomplete ?= {
          options: []
          set: set
        }
        return $q.when()
        .then ()->
          _fakeFilter = (value)->
            return _.uniq( value.split(' ') )
          mm.autocomplete.options = _fakeFilter(value)
          return mm.autocomplete

      submitBooking : (person, event, booking, onSuccess)->
        # some sanity checks
        if mm.confirmEventId != event.id
          toastr.warning("You are booking for a different event. title=" +
            event.title)
        if mm.confirmCurrentUserId != person.id
          toastr.warning("You are booking for a different person. name=" +
            person.displayName)

        participantIds = _.map $scope.vm.lookup['Participations'], 'participantId'
        return mm.createParticipation(person, event, booking, participantIds)
        .then (participation)->
          participation.type = 'Participation'
          participation.body.status = "new" # [new,pending,accept,reject]
          return participation
        .then (result)->
          # utils.ga_Send('send', 'event', 'participation'
          #   , 'event-booking', 'Yes', 10)
          onSuccess?(result)
          return result
        .catch (err)->
          if err=="DUPLICATE KEY"
            toastr.info "You are already participating in the event."
            # $scope.vm.activate()
            $timeout ()-> $scope.vm.on.scrollTo('cp-participant')
            return onSuccess?()
          $q.reject err
        return
    }

    once = $scope.$on 'modal.afterShow', (ev, modal)->
      if modal == $scope.modal
        mm.afterModalShow()
      once?()
      return

    console.log ["EventContributionCtrl initialized scope.$id=", $scope.$id]
    return mm

EventContributionCtrl.$inject = [
  '$scope', '$rootScope', '$q'
  'AAAHelpers'
  '$log', 'toastr'
]


angular.module 'starter.events'
  .controller 'EventContributionCtrl', EventContributionCtrl
