/* globals $ */
import _ from 'lodash';
import tv4 from 'tv4';

import * as errors from './errors';

// TODO: is quite silly to consider undefined as whitespace
export function isWhitespace(char) {
  return (char === ' ') || (char === '\n') || (char === undefined);
}

// NOTE: currently unused
export function isPunctuation(char) {
  return char === '.' || char === ',' || char === '!' || char === '?';
}

const urlRegex = /^https?:\/\/([^\s]+\.[^\s]+$|localhost)/;
export function isLink(word) {
  return urlRegex.test(word);
}

export function mimetypeLookup(filename) {
  const parts = filename.split('.');
  const extension = parts.length > 1 ? parts[parts.length - 1] : '';
  const extensionLookup = {
    'json': 'application/json',
    'txt': 'text/plain',
    '': 'text/plain'
  };
  return extensionLookup[extension.toLowerCase()];
}

export function isScrolledIntoView(elem, container) {
  const $elem = $(elem);
  const $container = $(container);

  const docViewTop = $container.offset().top;
  const docViewBottom = docViewTop + $container.outerHeight();

  const elemTop = $elem.offset().top;
  const elemBottom = elemTop + $elem.height();

  return ((elemBottom <= docViewBottom) && (elemTop >= docViewTop));
}

export function tv4_validate(data, schema, object='data') {
  // 3rd argument: checks recursive
  // 4th argument: bans unknown properties
  if (!tv4.validate(data, schema, true, true)) {
    throw new errors.GenericError(
      `Error validating ${object} schema ${JSON.stringify(data, null, 2)}: ${JSON.stringify(tv4.error)}`
    );
  }
}

// shim for filling in default values, with tv4
export function fill_tv4_defaults(data, schema) {
  for (const prop in schema.properties) {
    const prop_info = schema.properties[prop];
    if (!(prop in data)) {
      if ('default' in prop_info) {
        let def_val = prop_info['default'];
        if (typeof def_val !== 'function') {
          def_val = _.cloneDeep(def_val);
        }
        data[prop] = def_val;
      }
    }
    // recursively fill in defaults for objects
    if (prop_info.type === 'object') {
      if (!(prop in data)) {
        data[prop] = {};
      }
      exports.fill_tv4_defaults(data[prop], prop_info);
    }
  }
  return null;
}

export function download_file(filename, mimetype, content) {
  const exportDiv = $('#export');
  exportDiv.attr('download', filename);
  exportDiv.attr('href', `data: ${mimetype};charset=utf-8,${encodeURIComponent(content)}`);
  exportDiv[0].click();
  exportDiv.attr('download', null);
  return exportDiv.attr('href', null);
};

