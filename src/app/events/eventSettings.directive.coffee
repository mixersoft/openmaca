'use strict'

mtEventSettings = ($compile, EventsResource) ->
  return {
    restrict: 'E'
    # replace: true
    templateUrl: 'events/eventSettings.template.html'
    scope: {
      event: '='
      when: '='   # update startTime when dateTime fields change
      type: '@'
      onChange: '&'
    }
    link: (scope, element, attrs) ->
      scope.humanizedSetting = EventsResource.humanizeSettings( scope.event.setting, 'humanize')
      scope.$watch 'event.isPublic', (newV, oldV)->
        return if newV == oldV
        scope.onChange({eventIsPublic: newV})
        return

      scope.$watch 'humanizedSetting', (newV, oldV)->
        return if _.isEqual(newV, oldV)
        if newV.allowRsvpFriends != oldV.allowRsvpFriends
          scope.disableRsvpFriendsLimit = !newV.allowRsvpFriends
          scope.humanizedSetting.rsvpFriendsLimit = 1 if newV == false
        scope.event.setting = EventsResource.humanizeSettings(newV, 'decode')
        scope.onChange({eventSetting: scope.event.setting})
        return
      ,true

      scope.$watch 'event.setting', (newV, oldV)->
        return if _.isEqual(newV, oldV)
        scope.humanizedSetting = EventsResource.humanizeSettings( scope.event.setting, 'humanize')
      ,true

      return # $compile( element.contents())(scope)

  }


mtEventSettings.$inject = ['$compile', 'EventsResource']

angular
  .module 'starter.events'
  .directive 'mtEventSettings', mtEventSettings
