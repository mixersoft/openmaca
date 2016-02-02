# new-tile.directive.coffee
'use strict'

# directive:newTile
#   - create a new tile from a url parsing open-graph meta tags
#   - use appModalSvc modals for detail view
#   - allow manual editing of open-graph delegate-handle
#   - usage: <new-tile></new-tile>
#


MARKUP = {
  INPUT: """
    <input ng-model="dm.field" style="width:100%;" type="text" placeholder="Enter Title or Url"/>
    """
  MODAL:
    newTileUrl: "blocks/components/new-tile.template.html"
}


OpenGraph = ($q, $http )->
  OG_API_ENDPOINT ={
    active: null
    local: 'http://localhost:3333/methods/' + 'get-open-graph'
    remote: 'http://app.snaphappi.com:3333/og'
  }

  OG_API_ENDPOINT.active =
    if window.location.hostname == "localhost"
    then OG_API_ENDPOINT.local
    else OG_API_ENDPOINT.remote

  self = {
    matchUrl : (value)->
      # match a url inside a string
      # reMatchUrl = /(?:(?:https?|ftp):\/\/)(?:\S+(?::\S*)?@)?(?:(?!(?:10|127)(?:\.\d{1,3}){3})(?!(?:169\.254|192\.168)(?:\.\d{1,3}){2})(?!172\.(?:1[6-9]|2\d|3[0-1])(?:\.\d{1,3}){2})(?:[1-9]\d?|1\d\d|2[01]\d|22[0-3])(?:\.(?:1?\d{1,2}|2[0-4]\d|25[0-5])){2}(?:\.(?:[1-9]\d?|1\d\d|2[0-4]\d|25[0-4]))|(?:(?:[a-z\u00a1-\uffff0-9]-*)*[a-z\u00a1-\uffff0-9]+)(?:\.(?:[a-z\u00a1-\uffff0-9]-*)*[a-z\u00a1-\uffff0-9]+)*(?:\.(?:[a-z\u00a1-\uffff]{2,}))\.?)(?::\d{2,5})?(?:[/?#]\S*)?$/i
      # coffeelint: disable=max_line_length
      reMatchUrl = /(?:(?:https?|ftp):\/\/)(?:\S+(?::\S*)?@)?(?:(?!(?:10|127)(?:\.\d{1,3}){3})(?!(?:169\.254|192\.168)(?:\.\d{1,3}){2})(?!172\.(?:1[6-9]|2\d|3[0-1])(?:\.\d{1,3}){2})(?:[1-9]\d?|1\d\d|2[01]\d|22[0-3])(?:\.(?:1?\d{1,2}|2[0-4]\d|25[0-5])){2}(?:\.(?:[1-9]\d?|1\d\d|2[0-4]\d|25[0-4]))|(?:(?:[a-z\u00a1-\uffff0-9]-*)*[a-z\u00a1-\uffff0-9]+)(?:\.(?:[a-z\u00a1-\uffff0-9]-*)*[a-z\u00a1-\uffff0-9]+)*(?:\.(?:[a-z\u00a1-\uffff]{2,}))\.?)(?::\d{2,5})?(?:[/?#]\S*)?/i
      # coffeelint: enable=max_line_length
      found = value.match(reMatchUrl)
      return found?[0]
    get : (url)->
      return $http.get(OG_API_ENDPOINT.active, {
        params: {url: url}
      })
      .then (resp)->
        return $q.reject(resp) if resp.statusText != 'OK'
        return $q.reject('NOT FOUND') if _.isEmpty resp.data
        og = resp.data
        return og
      , (err)->
        if OG_API_ENDPOINT.active == OG_API_ENDPOINT.local
          OG_API_ENDPOINT.active = OG_API_ENDPOINT.remote
          console.log(['open-graph.get',err])
          return self.get(url)

    normalize : (og)->
      primaryFields = ['og:url', 'og:title', 'og:description', 'og:image', 'og:site_name']
      normalized = {}
      _.each _.pick( og, primaryFields ), (v,k)->
        normalized[ k.replace('og:','') ] = v
        return
      normalized['extras'] = _.omit og, primaryFields
      return normalized
  }
  return self
OpenGraph.$inject = ['$q', '$http']

TileHelpers = (appModalSvc, $q)->
  self = {
    modal_showTileEditor : (data)->
      options = {modalCallback: null}
      return appModalSvc.show(
        MARKUP.MODAL.newTileUrl
        , 'TileEditorCtrl as mm'
        , {
          data: data
        }
        , options )
      .then (result)->
        # wait for closeModal()
        result ?= 'CANCELED'
        console.log ['modal_showTileEditor()', result]
        if result == 'CANCELED'
          return $q.reject('CANCELED')
        return $q.reject(result) if result?['isError']

        return result
    isTileComplete: (data)->
      isComplete = _.reduce ['url', 'title', 'description', 'image'], (result, key)->
        return result = result && data[key]
      , true
      return isComplete

  }
  return self
TileHelpers.$inject = ['appModalSvc', '$q']

###
# @description TileEditorCtrl used by TileHelpers.modal_showTileEditor modal
###
TileEditorCtrl = (scope, $q, locationHelpers, $timeout, $cordovaGeolocation)->
  this.id = 'TileEditorCtrl'
  mm = this

  mm.geo = {
    setting:
      hasGeolocation: null
      show:
        spinner:
          location: false
        location: false
    errorMsg:
      location: null
    init: ()->
      mm.geo.setting.hasGeolocation = navigator.geolocation?
      mm.geo.setting.show.location = !!mm.data.address
      return
    handleGeolocationErr : (err)->
      ERROR_CODES = {
        1: 'PERMISSION_DENIED'
        2: 'POSITION_UNAVAILABLE'
        3: 'TIMEOUT'
      }
      switch ERROR_CODES[err.code]
        when 'PERMISSION_DENIED'
          mm.geo.errorMsg.location = """
          Permission Denied. Please check your privacy settings and try again.
          """
        when 'POSITION_UNAVAILABLE'
          mm.geo.errorMsg.location = "Warning: Position unavailable."
        else
          console.warn ['Err location', err]
      return
    geocodeAddress : (force)->
      if mm.data.latlon && mm.data.isCurrentLocation && force
        location = mm.data.latlon.join(',')
      if mm.data.latlon && !force
        console.log ['locationClick()', _.pick( mm.data, ['latlon','address'] ) ]
        return $q.when mm.data
      location ?= mm.data.address
      return if !location
      return locationHelpers.getLatLon( location )
      .then (result)->
        console.log ['locationClick()', result]
        mm.data.latlon = result?.location
        mm.data.address = result?.address
        return mm.data
  }

  mm.data = {
    url: null
    title: null
    description: null
    site_name: null
    image: null
    extras: null
    address: null
    latlon: null
  }





  mm.on = {
    cameraClick: (ev)->
      check = ev.currentTarget
      return

    # TODO: refactor, create directive:<item-input-location>
    locationClick: (ev, value )->
      mm.geo.errorMsg.location = null
      if value == 'CURRENT'
        mm.geo.setting.show.spinner.location = true
        promise = locationHelpers.getCurrentPosition()
        .finally ()->
          mm.geo.setting.show.spinner.location = false
      else
        if !value
          mm.geo.setting.show.location = true
          target = ev.currentTarget
          selector = '#new-tile-modal-view .location'
          $timeout ()->
            document.querySelector(selector).scrollIntoView()
          return $q.reject('ERROR: Expecting address')
        # note: geocodeSvc.geocode() will parse "lat,lon" values
        if mm.data.latlon && mm.data.isCurrentLocation
          return $q.when(value) # keep current latlon, just updating address field

        if mm.data.latlon
          # repeat: geocode current address
          promise = locationHelpers.geocodeAddress({address:value}, 'force')
        else
          promise = locationHelpers.geocodeAddress({address:value})

      return promise
      .then (result)->
        mm.data.latlon = result.latlon
        mm.data.address = result.address
      , (err)->
        mm.geo.errorMsg.location = err.humanize

      return

    done: (ev)->
      # post to $meteor
      mm.closeModal mm.data
  }

  ionic.Platform.ready ->
    mm.geo.init()
    return

  return
TileEditorCtrl.$inject = ['$scope', '$q', 'locationHelpers', '$timeout', '$cordovaGeolocation']



NewTileDirective = ($q, $compile, $timeout, openGraphSvc, tileHelpers)->
  directive = {
    restrict: 'E'
    # controllerAs: 'dm'
    # controller: 'TileEditorCtrl'
    # require: ['ngModel', 'newTile']
    # require: ['newTile'] # same as directive name
    scope: {
      'placeholderText': '@'
      'returnClose': '='
      'isFetching': '='
      'onReturn': '&'
      'onFocus': '&'
      'onBlur': '&'
      'onKeyDown': '&'
      'onComplete': '&'
      'cancelBlur': '='
    }
    link:
      pre: (scope, element, attrs, controllers) ->

        _reset = ()->
          dm.field = null
          dm.data = {}

        _getOpenGraph = (url)->
          scope.isFetching = true
          return openGraphSvc.get(url)
          .then (og)->
            scope.isFetching = false
            data = openGraphSvc.normalize(og)
            angular.extend dm.data, data
            # TODO?: merge with dm.data.field?
            dm.field = null
            return data
          , (err)->
            console.warn ['openGraphSvc.get()', err]
            return


        _showTileEditorAsModal = (data, force)->
          return $q.when()
          .then ()->
            return data if tileHelpers.isTileComplete(data) && !force
            return tileHelpers.modal_showTileEditor(data)
          .then (result)->
            scope.onComplete?({result: result})
          , (err)->
            scope.onComplete?({result: null})
          .finally _reset


        # initialize directive model (dm)
        scope.dm = dm = {
          enabled : false
          field : null
          data :
            url: null
            title: null
        }

        # input element, can be either url or title
        $field = $compile( MARKUP.INPUT )(scope)
        if scope.placeholderText
          $field.attr('placeholder', scope.placeholderText)
        element.append($field)

        scope.clear = (ev)->
          ev.stopImmediatePropagation()
          dm.field = null
          dm.enabled = false
          $timeout ()->
            return $field[0].focus()
          ,150

        $field.bind 'focus', (e)->
          dm.enabled = !dm.field
          scope.$apply()
          if attrs.onFocus
            $timeout ()-> scope.onFocus()
          return

        $field.bind 'blur', (e)->
          return if !dm.field
          return if scope.cancelBlur
          matched = openGraphSvc.matchUrl(dm.field)
          if matched
            if dm.data.url != matched
              dm.data.url = matched
              console.log "blur: "+dm.data.url
              _getOpenGraph( dm.data.url )
              .then (data)->
                return _showTileEditorAsModal(data)
          else
            dm.data.title = dm.field
            return _showTileEditorAsModal(dm.data, 'force')
          if attrs.onBlur
            $timeout ()->
              scope.onBlur()
              return
          return

        $field.bind 'keydown', (e)->
          if e.which == 13  # return
            if attrs.returnClose
              $field[0].blur()
            if attrs.onReturn
              $timeout ()-> scope.onReturn()
            return
          if e.which == 32 # space
            matched = openGraphSvc.matchUrl(dm.field)
            if matched
              dm.data.url = matched
              console.log "keydown: "+dm.data.url
              _getOpenGraph( dm.data.url )
              .then (data)->
                return _showTileEditorAsModal(data)
            else
              console.log "keydown: end in space but no match"
          if attrs.onKeyDown
            $timeout ()->
              scope.onKeyDown({
                value: dm.field
                set: (value)->
                  # hack: how can we let autocomplete set value properly?
                  dm.field = value
              })
              return
          dm.enabled = !dm.field
          scope.$apply()
          return



  }
  return directive


NewTileDirective.$inject = ['$q', '$compile', '$timeout', 'openGraphSvc', 'tileHelpers']


angular.module('blocks.components')
  .factory 'openGraphSvc', OpenGraph
  .factory 'tileHelpers', TileHelpers
  .controller 'TileEditorCtrl', TileEditorCtrl
  .directive 'newTile', NewTileDirective
