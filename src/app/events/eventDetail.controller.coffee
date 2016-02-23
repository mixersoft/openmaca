'use strict'

EventDetailCtrl = (
  $scope, $rootScope, $q, $location, $window, $timeout
  $ionicScrollDelegate, $state, $stateParams
  $log, toastr
  appModalSvc, tileHelpers, openGraphSvc
  uiGmapGoogleMapApi, geocodeSvc, unsplashItSvc
  UsersResource, EventsResource, IdeasResource, FeedResource
  EventActionHelpers, $filter, notificationTemplates
  utils, devConfig, exportDebug
  )->
    # coffeelint: disable=max_line_length
    # coffeelint: enable=max_line_length

    vm = this
    vm.title = "Event Detail"
    vm.viewId = ["event-detail-view",$scope.$id].join('-')
    vm.me = null      # current user, set in initialize()
    vm.acl = {
      isVisitor: ()->
        return true if !$rootScope.user
      isUser: ()->
        return true if $rootScope.user
    }
    vm.settings = {
      view:
        show: 'grid'
        'new': false
      show:
        'hideDetails': true
        'map':false
    }

    vm.lookup = {
      colors: ['royal', 'positive', 'calm', 'balanced', 'energized', 'assertive']
    }

    vm.event = {}

    vm.inviteActions = {
      requiresAction: (post, event, me)->
        event ?= vm.event
        me ?= vm.me
        check = {
          type: post.type == 'Invitation'
          status: ~['new', 'viewed'].indexOf(post.body.status)
        }
        nextAction = post.head.nextActionBy
        switch nextAction
          when 'owner'
            check['nextAction'] = me && event.$$owner == me
            # check['nextAction'] = me && event.moderatorId == me.id
          when 'recipient'
            check['nextAction'] = me && ~post.head.recipientIds.indexOf me.id
        return _.reject(check).length == 0

      accept: ($event, event, invitation)->
        return $q.when()
        .then ()->
          return if invitation.type != 'Invitation'

          invitation.body.status='viewed'
          return invitation
        .then (invitation)->
          return vm.on.beginBooking(vm.me, event)
        .then (participation)->
          return if !participation
          invitation.body.status='closed'
          invitation.body.response = 'accepted'
          # append a log as a comment to invitation
          invitation.body.seats = participation.body.seats
          return vm.inviteActions._logAction(event, invitation, vm)
          .then (invitation)->
            target = $event.target
            $wrap = angular.element utils.getChildOfParent(target, 'item-post', '.post-comments')
            $wrap.removeClass('hide')
          .then (invitation)->
            toastr.info("DEMO: invitation responses will be automatically accepted.")
            return $timeout(3000)
          .then ()->
            # TODO: need to change ParticipationResponse.head.ownerId
            vm.moderatorActions.accept($event, event, participation)


      message: ($event, event, invitation)->
        return $q.when()
        .then ()->
          invitation.body.status='viewed'
          return vm.postActions.showCommentForm($event)

      decline: ($event, event, invitation)->
        return $q.when()
        .then ()->
          return if invitation.type != 'Invitation'

          invitation.body.status='closed'
          invitation.body.response = 'declined'
          # append a log as a comment to invitation
          return vm.inviteActions._logAction(event, invitation, vm)
        .then (result)->
          message = notificationTemplates.get('invitation.declined.ownerId', invitation)
          notify = {
            ownerId: invitation.head.ownerId
            # role: 'participants'
            message: message
          }
          return EventActionHelpers.FeedHelpers.notify(event, notify, vm)

          # # show Post.comments
          # target = $event.target
          # $wrap = angular.element utils.getChildOfParent(target, 'item-post', '.post-comments')
          # $wrap.removeClass('hide')


      _logAction: (event, invitation, vm)->
        options = {
          log: true
          message: [
            vm.me.displayName
            'has', invitation.body.response
          ]
        }
        switch invitation.body.response
          when 'declined'
            options.message.push 'this invitation.'
          when 'accepted'
            options.message = options.message.concat [
              'this invitation, and requested'
              invitation.body.seats
              'seats.'
            ]
          else
            return

        # TODO set 'moderatorId' to new participantId
        #   log/add notification to feed (dismissable), '[person] accepted your invitation'
        return vm.postActions.postComment(null, invitation, options)



    }

    vm.moderatorActions = {
      requiresAction: (post, event, me)->
        event ?= vm.event
        me ?= vm.me
        check = {
          type: post.type == 'Participation'
          status: ~['new', 'pending'].indexOf(post.body.status)
          response: ~['Yes','Message'].indexOf post.body.response
        }

        nextAction = post.head.nextActionBy
        switch nextAction
          when 'moderator', 'owner'
            check['nextAction'] = me && event.ownerId == me.id
            # check['nextAction'] = me && event.moderatorId == me.id
          when 'recipient'
            check['nextAction'] = me && ~post.head.recipientIds.indexOf me.id
        return _.reject(check).length == 0

      accept: ($event, event, participation)->
        return $q.when()
        .then ()->
          return if participation.type != 'Participation'

          participation.body.status='accepted'
          return participation
        .then (participation)->
          # update event to include participation
          return EventActionHelpers.createBooking(event, participation, vm)
        .then (event)->
          $scope.$emit 'user:event-role-changed', participation.head.$$owner, event
          return vm.moderatorActions._logAction(event, participation, vm)
        .then ()->
          promises = []
          notify = {
            ownerId: participation.head.ownerId
            message: notificationTemplates.get('booking.accepted.ownerId', participation)
          }
          if _.isEmpty participation.body.attachment
            notify.message = [
              notify.message
              '<br /><br />'
              notificationTemplates.get('event.contributions.reminder', participation)
            ]
          promises.push notifyNewBooking = EventActionHelpers.FeedHelpers.notify(event, notify, vm)

          notify = {
            ownerId: event.ownerId
            # role: 'participants'
            recipientIds: _.difference event.participantIds, [participation.head.ownerId]
            message: notificationTemplates.get('booking.accepted.participantIds', participation)
            contribution: participation.body.attachment
          }
          if not _.isEmpty participation.body.attachment
            notify.message = [
              notify.message
              '<br /><br />'
              notificationTemplates.get('event.contributions.notify', participation)
            ]
          promises.push notifyOthers = EventActionHelpers.FeedHelpers.notify(event, notify, vm)

          return $q.all(promises)
          .then ()->
            if event.seatsOpen > 0
              event.moderatorId = participation.head.ownerId
              post = {
                ownerId: participation.head.ownerId
                displayName: participation.head.$$owner.displayName
                seatsOpen: event.seatsOpen
                toNow: moment(event.startTime).fromNow()
              }
              post.message = notificationTemplates.get('event.booking.sendInvites', post)
              promises.push sendInvites = EventActionHelpers.FeedHelpers.notify(event, post, vm)
            else
              post = {
                hostName: event.$$host.displayName
                role: 'participants'
              }
              post.message = notificationTemplates.get('event.booking.fullyBooked', post)
              promises.push fullyBooked = EventActionHelpers.FeedHelpers.notify(event, post, vm)
            return $q.all(promises)

      message: ($event, event, participation)->
        return $q.when()
        .then ()->
          participation.body.status='pending'
          return vm.postActions.showCommentForm($event)

      decline: ($event, event, participation)->
        return $q.when()
        .then ()->
          return if participation.type != 'Participation'

          participation.body.status='declined'
          # update participation, post to Server
          return participation
        .then (participation)->
          return vm.moderatorActions._logAction(event, participation, vm)
        .then ()->
          notify = {
            ownerId: participation.head.ownerId
            # role: 'participants'
            message: notificationTemplates.get('booking.decline.ownerId', participation)
          }
          return EventActionHelpers.FeedHelpers.notify(event, notify, vm)

      _logAction: (event, participation, vm)->
        # log ParticipationResponse
        action = {
          head:
            ownerId: vm.me.id
          body:
            type: 'ParticipationResponse'
            action: participation.body.status  # ['accepted', 'declined']
            participationId: participation.id
            $$participation: participation
            comment: ''
        }
        if participation.body.status=='declined'
          # make rejected private (Notification?)
          action.head['recipientIds'] = [participation.head.ownerId]
        $scope.$emit 'event:feed-changed', [event, action]
        return EventActionHelpers.FeedHelpers.log(event, action, vm)

    }

    vm.feed = {
      postDefaults: {}
      show:
        messageComposer: false
      showMessageComposer: ($event, event, post)->
        # template for post.body
        # for post.head: {} # see: FeedHelpers.post()
        this.postDefaults = {
          message: null
          attachment: null
          address: null
          location: null
        }
        this.show.messageComposer = true
        parent = ionic.DomUtil.getParentWithClass($event.target, 'event-detail')
        $timeout().then ()->
          textbox = parent.querySelector('message-composer textarea')
          textbox.focus()
          textbox.scrollIntoViewIfNeeded()
        return
    }

    # TODO: make directive
    vm.postActions = {
      acl : {
        isModerator: (event, post)->
          return true if event.moderatorId == vm.me.id
          return true if post.head.moderatorIds? && ~post.head.moderatorIds.indexOf vm.me.id
          return true if event.ownerId == vm.me.id
          # console.info "DEMO: isModerator() == true"
          # return true
      }
      dismissItem: ($event, item)->
        item.head['dismissedBy'] ?= []
        item.head['dismissedBy'].push vm.me.id
        return FeedResource.update(item.id, item)
        .then (result)->
          # TODO: animate offscreen before removal
          found = _.findIndex vm.event.feed, {id: result.id}
          vm.event.feed[found] = result if ~found
          $rootScope.$emit 'event:feed-changed', vm.event, vm.me

          return
      like: ($event, post)->
        post.head.likes ?= []
        #TODO: should add Ids to the array, not object
        found = post.head.likes.indexOf(vm.me)
        if ~found
          post.head.likes.splice(found,1) # unlike
        else
          post.head.likes.push(vm.me)

      showCommentForm: ($event)->
        target = $event.currentTarget
        # parent = ionic.DomUtil.getParentWithClass(target,'item-post')
        # $wrap = angular.element parent.querySelector('.post-comments')
        $wrap = angular.element utils.getChildOfParent(target, 'item-post', '.post-comments')
        $wrap.toggleClass('hide')
        return if $wrap.hasClass('hide')
        $timeout().then ()->
          textbox = $wrap[0].querySelector('textarea.comment')
          textbox.focus()
          textbox.scrollIntoViewIfNeeded()

      ###
      # @description Post comment to a Feed Post
      # @params options Obj, {log:boolean, message:String}
      ###
      postComment: ($event, post, options)->
        if !options
          target = $event.currentTarget
          # parent = ionic.DomUtil.getParentWithClass(target, 'comment-form')
          # commentField = parent.querySelector('textarea.comment')
          commentField = utils.getChildOfParent(target, 'comment-form', 'textarea.comment')
          comment = angular.copy commentField.value
        else
          comment = options.message
          comment = comment.join(' ') if _.isArray comment

        return $q.when() if not comment

        return $q.when()
        .then ()->
          from = vm.me
          if options?['log'] == true
            # TODO: ???: has post from syslog("feed") been replaced by "Notifications"?
            from = {
              id: 'syslog'
              displayName: 'feed:'
              face: unsplashItSvc.getImgSrc(0,'syslog',{face:true})
            }

          postComment = {
            type: "PostComment"
            head:
              id: Date.now()
              ownerId: from.id + ''
              $$owner: from
              target: # parent post for this comment
                id: post.head.id
                class: post.type
              createdAt: new Date()
              likes: []
            body:
              comment: comment
          }
          if commentField?
            commentField.value = ''
          return [post, postComment]
        .then (result)->
          [post, postComment] = result
          post.body.comments ?= []
          post.body.comments.push postComment
          return post
    }

    vm.location = {
      GRID_RESPONSIVE_SM_BREAK: 680
      map: null
      prepareMap: (event, options)->
        return $q.when() if !event.location

        return uiGmapGoogleMapApi
        .then ()->
          # markerCount==1
          mapOptions = {
            type: 'oneMarker'
            location: event.location
            draggableMarker: false
            dragendMarker: (marker, eventName, args)->
              return
          }
          mapOptions = _.extend mapOptions, {
            'control' : {}
            'mapReady' : (map, eventName)->
              $scope.$broadcast 'map-ready', map
          }, options
          mapConfig = geocodeSvc.getMapConfig mapOptions
          # mapConfig.zoom = 11
          return mapConfig
      showOnMap: (event, options)->
        return vm.location.prepareMap(event, options)
        .then (config)->
          vm.location.map = config
          vm.settings.show.map = true if options.visible
          exportDebug.set 'mapConfig', config
          return

    }

    vm.dev = {
      loginByRole : (event, forceRole)->
        userId = null
        $rootScope.demoRole = forceRole if forceRole
        switch $rootScope.demoRole
          when 'host'
            userId = event.ownerId
          when 'participant' # userId < 4
            userId = _.sample event.participantIds[1...event.participantIds.length]
          when 'booking'
            userId = '5'
          when 'invited'
            userId = '6'
          when 'visitor'
            userId = '7'
        return $q.when() if !userId
        return devConfig.loginUser(userId, 'force')
        .then (user)->
          vm.me = user
          $scope.$broadcast 'demo-role:changed', $rootScope.demoRole if forceRole
          return user
        .finally ()->
          toastr.info [
            "You are now "
            vm.me.displayName
            ", role="
            $rootScope.demoRole.toUpperCase()
          ].join('')

      addRoleToUser : ()->
        return devConfig.dataReady.finally ()->
          return if !vm.event.participantIds

          if vm.me.id == vm.event.ownerId
            role = 'host'
          else if ~vm.event.participantIds.indexOf vm.me.id
            role = 'participant'
          else if vm.me.id == '5'
            role = 'booking'
          else if vm.me.id == '6'
            role = 'invitation'
          else
            role = 'visitor'
          vm.me.role = role
          console.info "addRoleToUser(), role="+role
          setFabIcon()
    }


    getData = ()->
      $q.when()
      .then ()->
        users = UsersResource.query()
        menuItems = IdeasResource.query()
        feed = FeedResource.query()
        return $q.all([users, menuItems, feed])
      .then (result)->
        [users, menuItems, feed] = result
        vm.lookup.users = users
        vm.lookup.menuItems = menuItems
        vm.lookup.feed = feed
      .then ()->
        # $filter('eventFeedFilter')(event, me)
        _.each vm.lookup.feed, (post)->
          # add $$owner to FEED posts
          post.head ?= {}
          post.head.$$owner = _.find(vm.lookup.users, {id: post.head.ownerId})
          if _.isEmpty post.head.recipientIds
            post.head.likes = [_.sample(vm.lookup.users)]

          # chatWith
          if post.head.recipientIds?[0]
            post.head.$$chatWith = _.find(vm.lookup.users, {id: post.head.recipientIds[0]})
          return

      .then ()->
        return EventsResource.query()
      .then (events)->
        vm.events = []
        _.each events, (event, i)->
          console.warn("TESTDATA: using currentUser as event Moderator")
          event.visibleAddress = event.address
          event.isPostModerator = vm.postActions.acl.isModerator
          event.moderatorId = event.ownerId
          vm.events.push event
          return
        return events



    setFabIcon = ()->
      vm.settings.show.fabIcon = 'ion-load-d' if !vm.me

      icon = null
      switch vm.me?.role
        when 'host', 'participant', 'booking'
          # edit event
          icon = 'ion-chatbox'
        when 'invitation','visitor'
          # join
          icon = 'ion-plus'
      # console.log ["FabIcon=" + icon, vm.me.role]
      vm.settings.show.fabIcon = icon



    vm.on = {
      scrollTo: (anchor)->
        $location.hash(anchor)
        $ionicScrollDelegate.anchorScroll(true)
        return

      setView: (value)->
        if 'value==null'
          next = if vm.settings.show == 'grid' then 'list' else 'grid'
          return vm.settings.view.show = next
        return vm.settings.view.show = value

      fabClick: ()->
        switch vm.me.role
          when 'host', 'participant', 'booking'
            # edit event
            return vm.feed.showMessageComposer()

          when 'invitation','visitor'
            # join
            return vm.on['beginBooking'](vm.me, vm.event)
        return

      # TODO: change params to (event, person)
      'beginBooking': (person, event)->
        return EventActionHelpers.bookingWizard(person, event, vm)
        .then (participation)->
          return if participation == 'CANCELED'
          return EventActionHelpers.FeedHelpers.post(event, participation, vm)
        .then (participation)->
          return participation

      'postCommentToFeed': (comment)->
        data = {
          type: 'Comment'
          head:
            isPublic: true
          body: comment
        }
        return EventActionHelpers.FeedHelpers.post(vm.event, data, vm)
        .then ()->
          console.log ['postToFeed', comment]
          # reset message-console and hide
          vm.feed.show.messageComposer = false
          vm.feed.post={}
      'toggleMap': ($event)->
        $event.preventDefault()
        event.stopImmediatePropagation()
        vm.settings.show.map = !vm.settings.show.map

        # console.log ['toggleMap', vm.settings.show.map]
      notReady: (value)->
        toastr.info "Sorry, " + value + " is not available yet"
        return false


    }

    initialize = ()->
      # $ionicView.loaded: called once for EACH cached $ionicView,
      #   i.e. each instance of vm
      return


    activate = ()->
      return $q.reject("ERROR: expecting event.id") if not $stateParams.id
      return devConfig.dataReady
      .finally ()->
        getData()
      .then (events)->
        vm.me = $rootScope.user
        index = $stateParams.id
        vm.event = vm.events[index]
        if !$rootScope.demoRole
          $rootScope.demoRole = 'invited'
        return vm.dev.loginByRole(vm.event).then vm.dev.addRoleToUser
      .then ()->
        event = vm.event
        $scope.$emit 'user:event-role-changed', null, event
        event.feed = vm.lookup.feed
        # event.feed = $filter('feedFilter')(event, FEED)
        event.$$paddedParticipants = $filter('eventParticipantsFilter')(event)

        deviceW = $window.innerWidth < vm.location.GRID_RESPONSIVE_SM_BREAK
        mapOptions = {
          visible: not deviceW
          draggableMap: not deviceW  # can't scroll in mobile view
        }
        promise = vm.location.showOnMap(event, mapOptions)
        return event
      .then (event)->
        exportDebug.set('event', event)
        # // Set Ink
        ionic.material?.ink.displayEffect()
        ionic.material?.motion.fadeSlideInRight({
          startVelocity: 2000
          })
        return

    resetMaterialMotion = (motion, parentId)->
      className = {
        'fadeSlideInRight': '.animate-fade-slide-in-right'
        'blinds': '.animate-blinds'
        'ripple': '.animate-ripple'
      }
      selector = '{aniClass} .item'.replace('{aniClass}', className[motion] )
      selector = '#'+ parentId + ' ' + selector if parentId?
      angular.element(document.querySelectorAll(selector))
        .removeClass('in')
        .removeClass('done')

    $scope.$watch 'vm.me', (newV)->
      return if !newV
      vm.me.role = null
      vm.dev.addRoleToUser()

    $scope.$on '$ionicView.loaded', (e)->
      # $log.info "viewLoaded for EventDetailCtrl, $scope.$id=" + e.currentScope.$id
      initialize()


    $scope.$on '$ionicView.enter', (e)->
      # $log.info "viewEnter for EventDetailCtrl"
      activate()

    $scope.$on '$ionicView.leave', (e) ->
      resetMaterialMotion('fadeSlideInRight')

    $scope.$on 'demo-role:changed', (ev, newV)->
      console.info ['demo-role:changed', newV]
      return if !newV
      # $rootScope.demoRole = newV
      # ev.stopPropagation()
      # ev.preventDefault()
      return vm.dev.loginByRole(vm.event) if vm.event

    $scope.$on 'user:event-role-changed', (ev, user, event)->
      return !user
      console.info ['user:event-role-changed', user.id]
      # ev.stopPropagation()
      ev.preventDefault()
      return vm.dev.addRoleToUser()


    loadOnce = ()->
      return if ~$rootScope['loadOnce'].indexOf 'EventDetailCtrl'
      $rootScope['loadOnce'].push 'EventDetailCtrl'
      # load $rootScope listeners only once

    loadOnce()

    return vm  # end EventDetailCtrl


EventDetailCtrl.$inject = [
  '$scope', '$rootScope', '$q', '$location', '$window', '$timeout'
  '$ionicScrollDelegate', '$state', '$stateParams'
  '$log', 'toastr'
  'appModalSvc', 'tileHelpers', 'openGraphSvc'
  'uiGmapGoogleMapApi', 'geocodeSvc', 'unsplashItSvc'
  'UsersResource', 'EventsResource', 'IdeasResource', 'FeedResource'
  'EventActionHelpers', '$filter', 'notificationTemplates'
  'utils', 'devConfig', 'exportDebug'
]


angular.module 'starter.events'
  .controller 'EventDetailCtrl', EventDetailCtrl
