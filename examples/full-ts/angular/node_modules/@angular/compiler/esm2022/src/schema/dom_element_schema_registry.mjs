/**
 * @license
 * Copyright Google LLC All Rights Reserved.
 *
 * Use of this source code is governed by an MIT-style license that can be
 * found in the LICENSE file at https://angular.io/license
 */
import { CUSTOM_ELEMENTS_SCHEMA, NO_ERRORS_SCHEMA, SecurityContext } from '../core';
import { isNgContainer, isNgContent } from '../ml_parser/tags';
import { dashCaseToCamelCase } from '../util';
import { SECURITY_SCHEMA } from './dom_security_schema';
import { ElementSchemaRegistry } from './element_schema_registry';
const BOOLEAN = 'boolean';
const NUMBER = 'number';
const STRING = 'string';
const OBJECT = 'object';
/**
 * This array represents the DOM schema. It encodes inheritance, properties, and events.
 *
 * ## Overview
 *
 * Each line represents one kind of element. The `element_inheritance` and properties are joined
 * using `element_inheritance|properties` syntax.
 *
 * ## Element Inheritance
 *
 * The `element_inheritance` can be further subdivided as `element1,element2,...^parentElement`.
 * Here the individual elements are separated by `,` (commas). Every element in the list
 * has identical properties.
 *
 * An `element` may inherit additional properties from `parentElement` If no `^parentElement` is
 * specified then `""` (blank) element is assumed.
 *
 * NOTE: The blank element inherits from root `[Element]` element, the super element of all
 * elements.
 *
 * NOTE an element prefix such as `:svg:` has no special meaning to the schema.
 *
 * ## Properties
 *
 * Each element has a set of properties separated by `,` (commas). Each property can be prefixed
 * by a special character designating its type:
 *
 * - (no prefix): property is a string.
 * - `*`: property represents an event.
 * - `!`: property is a boolean.
 * - `#`: property is a number.
 * - `%`: property is an object.
 *
 * ## Query
 *
 * The class creates an internal squas representation which allows to easily answer the query of
 * if a given property exist on a given element.
 *
 * NOTE: We don't yet support querying for types or events.
 * NOTE: This schema is auto extracted from `schema_extractor.ts` located in the test folder,
 *       see dom_element_schema_registry_spec.ts
 */
// =================================================================================================
// =================================================================================================
// =========== S T O P   -  S T O P   -  S T O P   -  S T O P   -  S T O P   -  S T O P  ===========
// =================================================================================================
// =================================================================================================
//
//                       DO NOT EDIT THIS DOM SCHEMA WITHOUT A SECURITY REVIEW!
//
// Newly added properties must be security reviewed and assigned an appropriate SecurityContext in
// dom_security_schema.ts. Reach out to mprobst & rjamet for details.
//
// =================================================================================================
const SCHEMA = [
    '[Element]|textContent,%ariaAtomic,%ariaAutoComplete,%ariaBusy,%ariaChecked,%ariaColCount,%ariaColIndex,%ariaColSpan,%ariaCurrent,%ariaDescription,%ariaDisabled,%ariaExpanded,%ariaHasPopup,%ariaHidden,%ariaKeyShortcuts,%ariaLabel,%ariaLevel,%ariaLive,%ariaModal,%ariaMultiLine,%ariaMultiSelectable,%ariaOrientation,%ariaPlaceholder,%ariaPosInSet,%ariaPressed,%ariaReadOnly,%ariaRelevant,%ariaRequired,%ariaRoleDescription,%ariaRowCount,%ariaRowIndex,%ariaRowSpan,%ariaSelected,%ariaSetSize,%ariaSort,%ariaValueMax,%ariaValueMin,%ariaValueNow,%ariaValueText,%classList,className,elementTiming,id,innerHTML,*beforecopy,*beforecut,*beforepaste,*fullscreenchange,*fullscreenerror,*search,*webkitfullscreenchange,*webkitfullscreenerror,outerHTML,%part,#scrollLeft,#scrollTop,slot' +
        /* added manually to avoid breaking changes */
        ',*message,*mozfullscreenchange,*mozfullscreenerror,*mozpointerlockchange,*mozpointerlockerror,*webglcontextcreationerror,*webglcontextlost,*webglcontextrestored',
    '[HTMLElement]^[Element]|accessKey,autocapitalize,!autofocus,contentEditable,dir,!draggable,enterKeyHint,!hidden,!inert,innerText,inputMode,lang,nonce,*abort,*animationend,*animationiteration,*animationstart,*auxclick,*beforexrselect,*blur,*cancel,*canplay,*canplaythrough,*change,*click,*close,*contextmenu,*copy,*cuechange,*cut,*dblclick,*drag,*dragend,*dragenter,*dragleave,*dragover,*dragstart,*drop,*durationchange,*emptied,*ended,*error,*focus,*formdata,*gotpointercapture,*input,*invalid,*keydown,*keypress,*keyup,*load,*loadeddata,*loadedmetadata,*loadstart,*lostpointercapture,*mousedown,*mouseenter,*mouseleave,*mousemove,*mouseout,*mouseover,*mouseup,*mousewheel,*paste,*pause,*play,*playing,*pointercancel,*pointerdown,*pointerenter,*pointerleave,*pointermove,*pointerout,*pointerover,*pointerrawupdate,*pointerup,*progress,*ratechange,*reset,*resize,*scroll,*securitypolicyviolation,*seeked,*seeking,*select,*selectionchange,*selectstart,*slotchange,*stalled,*submit,*suspend,*timeupdate,*toggle,*transitioncancel,*transitionend,*transitionrun,*transitionstart,*volumechange,*waiting,*webkitanimationend,*webkitanimationiteration,*webkitanimationstart,*webkittransitionend,*wheel,outerText,!spellcheck,%style,#tabIndex,title,!translate,virtualKeyboardPolicy',
    'abbr,address,article,aside,b,bdi,bdo,cite,content,code,dd,dfn,dt,em,figcaption,figure,footer,header,hgroup,i,kbd,main,mark,nav,noscript,rb,rp,rt,rtc,ruby,s,samp,section,small,strong,sub,sup,u,var,wbr^[HTMLElement]|accessKey,autocapitalize,!autofocus,contentEditable,dir,!draggable,enterKeyHint,!hidden,innerText,inputMode,lang,nonce,*abort,*animationend,*animationiteration,*animationstart,*auxclick,*beforexrselect,*blur,*cancel,*canplay,*canplaythrough,*change,*click,*close,*contextmenu,*copy,*cuechange,*cut,*dblclick,*drag,*dragend,*dragenter,*dragleave,*dragover,*dragstart,*drop,*durationchange,*emptied,*ended,*error,*focus,*formdata,*gotpointercapture,*input,*invalid,*keydown,*keypress,*keyup,*load,*loadeddata,*loadedmetadata,*loadstart,*lostpointercapture,*mousedown,*mouseenter,*mouseleave,*mousemove,*mouseout,*mouseover,*mouseup,*mousewheel,*paste,*pause,*play,*playing,*pointercancel,*pointerdown,*pointerenter,*pointerleave,*pointermove,*pointerout,*pointerover,*pointerrawupdate,*pointerup,*progress,*ratechange,*reset,*resize,*scroll,*securitypolicyviolation,*seeked,*seeking,*select,*selectionchange,*selectstart,*slotchange,*stalled,*submit,*suspend,*timeupdate,*toggle,*transitioncancel,*transitionend,*transitionrun,*transitionstart,*volumechange,*waiting,*webkitanimationend,*webkitanimationiteration,*webkitanimationstart,*webkittransitionend,*wheel,outerText,!spellcheck,%style,#tabIndex,title,!translate,virtualKeyboardPolicy',
    'media^[HTMLElement]|!autoplay,!controls,%controlsList,%crossOrigin,#currentTime,!defaultMuted,#defaultPlaybackRate,!disableRemotePlayback,!loop,!muted,*encrypted,*waitingforkey,#playbackRate,preload,!preservesPitch,src,%srcObject,#volume',
    ':svg:^[HTMLElement]|!autofocus,nonce,*abort,*animationend,*animationiteration,*animationstart,*auxclick,*beforexrselect,*blur,*cancel,*canplay,*canplaythrough,*change,*click,*close,*contextmenu,*copy,*cuechange,*cut,*dblclick,*drag,*dragend,*dragenter,*dragleave,*dragover,*dragstart,*drop,*durationchange,*emptied,*ended,*error,*focus,*formdata,*gotpointercapture,*input,*invalid,*keydown,*keypress,*keyup,*load,*loadeddata,*loadedmetadata,*loadstart,*lostpointercapture,*mousedown,*mouseenter,*mouseleave,*mousemove,*mouseout,*mouseover,*mouseup,*mousewheel,*paste,*pause,*play,*playing,*pointercancel,*pointerdown,*pointerenter,*pointerleave,*pointermove,*pointerout,*pointerover,*pointerrawupdate,*pointerup,*progress,*ratechange,*reset,*resize,*scroll,*securitypolicyviolation,*seeked,*seeking,*select,*selectionchange,*selectstart,*slotchange,*stalled,*submit,*suspend,*timeupdate,*toggle,*transitioncancel,*transitionend,*transitionrun,*transitionstart,*volumechange,*waiting,*webkitanimationend,*webkitanimationiteration,*webkitanimationstart,*webkittransitionend,*wheel,%style,#tabIndex',
    ':svg:graphics^:svg:|',
    ':svg:animation^:svg:|*begin,*end,*repeat',
    ':svg:geometry^:svg:|',
    ':svg:componentTransferFunction^:svg:|',
    ':svg:gradient^:svg:|',
    ':svg:textContent^:svg:graphics|',
    ':svg:textPositioning^:svg:textContent|',
    'a^[HTMLElement]|charset,coords,download,hash,host,hostname,href,hreflang,name,password,pathname,ping,port,protocol,referrerPolicy,rel,%relList,rev,search,shape,target,text,type,username',
    'area^[HTMLElement]|alt,coords,download,hash,host,hostname,href,!noHref,password,pathname,ping,port,protocol,referrerPolicy,rel,%relList,search,shape,target,username',
    'audio^media|',
    'br^[HTMLElement]|clear',
    'base^[HTMLElement]|href,target',
    'body^[HTMLElement]|aLink,background,bgColor,link,*afterprint,*beforeprint,*beforeunload,*blur,*error,*focus,*hashchange,*languagechange,*load,*message,*messageerror,*offline,*online,*pagehide,*pageshow,*popstate,*rejectionhandled,*resize,*scroll,*storage,*unhandledrejection,*unload,text,vLink',
    'button^[HTMLElement]|!disabled,formAction,formEnctype,formMethod,!formNoValidate,formTarget,name,type,value',
    'canvas^[HTMLElement]|#height,#width',
    'content^[HTMLElement]|select',
    'dl^[HTMLElement]|!compact',
    'data^[HTMLElement]|value',
    'datalist^[HTMLElement]|',
    'details^[HTMLElement]|!open',
    'dialog^[HTMLElement]|!open,returnValue',
    'dir^[HTMLElement]|!compact',
    'div^[HTMLElement]|align',
    'embed^[HTMLElement]|align,height,name,src,type,width',
    'fieldset^[HTMLElement]|!disabled,name',
    'font^[HTMLElement]|color,face,size',
    'form^[HTMLElement]|acceptCharset,action,autocomplete,encoding,enctype,method,name,!noValidate,target',
    'frame^[HTMLElement]|frameBorder,longDesc,marginHeight,marginWidth,name,!noResize,scrolling,src',
    'frameset^[HTMLElement]|cols,*afterprint,*beforeprint,*beforeunload,*blur,*error,*focus,*hashchange,*languagechange,*load,*message,*messageerror,*offline,*online,*pagehide,*pageshow,*popstate,*rejectionhandled,*resize,*scroll,*storage,*unhandledrejection,*unload,rows',
    'hr^[HTMLElement]|align,color,!noShade,size,width',
    'head^[HTMLElement]|',
    'h1,h2,h3,h4,h5,h6^[HTMLElement]|align',
    'html^[HTMLElement]|version',
    'iframe^[HTMLElement]|align,allow,!allowFullscreen,!allowPaymentRequest,csp,frameBorder,height,loading,longDesc,marginHeight,marginWidth,name,referrerPolicy,%sandbox,scrolling,src,srcdoc,width',
    'img^[HTMLElement]|align,alt,border,%crossOrigin,decoding,#height,#hspace,!isMap,loading,longDesc,lowsrc,name,referrerPolicy,sizes,src,srcset,useMap,#vspace,#width',
    'input^[HTMLElement]|accept,align,alt,autocomplete,!checked,!defaultChecked,defaultValue,dirName,!disabled,%files,formAction,formEnctype,formMethod,!formNoValidate,formTarget,#height,!incremental,!indeterminate,max,#maxLength,min,#minLength,!multiple,name,pattern,placeholder,!readOnly,!required,selectionDirection,#selectionEnd,#selectionStart,#size,src,step,type,useMap,value,%valueAsDate,#valueAsNumber,#width',
    'li^[HTMLElement]|type,#value',
    'label^[HTMLElement]|htmlFor',
    'legend^[HTMLElement]|align',
    'link^[HTMLElement]|as,charset,%crossOrigin,!disabled,href,hreflang,imageSizes,imageSrcset,integrity,media,referrerPolicy,rel,%relList,rev,%sizes,target,type',
    'map^[HTMLElement]|name',
    'marquee^[HTMLElement]|behavior,bgColor,direction,height,#hspace,#loop,#scrollAmount,#scrollDelay,!trueSpeed,#vspace,width',
    'menu^[HTMLElement]|!compact',
    'meta^[HTMLElement]|content,httpEquiv,media,name,scheme',
    'meter^[HTMLElement]|#high,#low,#max,#min,#optimum,#value',
    'ins,del^[HTMLElement]|cite,dateTime',
    'ol^[HTMLElement]|!compact,!reversed,#start,type',
    'object^[HTMLElement]|align,archive,border,code,codeBase,codeType,data,!declare,height,#hspace,name,standby,type,useMap,#vspace,width',
    'optgroup^[HTMLElement]|!disabled,label',
    'option^[HTMLElement]|!defaultSelected,!disabled,label,!selected,text,value',
    'output^[HTMLElement]|defaultValue,%htmlFor,name,value',
    'p^[HTMLElement]|align',
    'param^[HTMLElement]|name,type,value,valueType',
    'picture^[HTMLElement]|',
    'pre^[HTMLElement]|#width',
    'progress^[HTMLElement]|#max,#value',
    'q,blockquote,cite^[HTMLElement]|',
    'script^[HTMLElement]|!async,charset,%crossOrigin,!defer,event,htmlFor,integrity,!noModule,%referrerPolicy,src,text,type',
    'select^[HTMLElement]|autocomplete,!disabled,#length,!multiple,name,!required,#selectedIndex,#size,value',
    'slot^[HTMLElement]|name',
    'source^[HTMLElement]|#height,media,sizes,src,srcset,type,#width',
    'span^[HTMLElement]|',
    'style^[HTMLElement]|!disabled,media,type',
    'caption^[HTMLElement]|align',
    'th,td^[HTMLElement]|abbr,align,axis,bgColor,ch,chOff,#colSpan,headers,height,!noWrap,#rowSpan,scope,vAlign,width',
    'col,colgroup^[HTMLElement]|align,ch,chOff,#span,vAlign,width',
    'table^[HTMLElement]|align,bgColor,border,%caption,cellPadding,cellSpacing,frame,rules,summary,%tFoot,%tHead,width',
    'tr^[HTMLElement]|align,bgColor,ch,chOff,vAlign',
    'tfoot,thead,tbody^[HTMLElement]|align,ch,chOff,vAlign',
    'template^[HTMLElement]|',
    'textarea^[HTMLElement]|autocomplete,#cols,defaultValue,dirName,!disabled,#maxLength,#minLength,name,placeholder,!readOnly,!required,#rows,selectionDirection,#selectionEnd,#selectionStart,value,wrap',
    'time^[HTMLElement]|dateTime',
    'title^[HTMLElement]|text',
    'track^[HTMLElement]|!default,kind,label,src,srclang',
    'ul^[HTMLElement]|!compact,type',
    'unknown^[HTMLElement]|',
    'video^media|!disablePictureInPicture,#height,*enterpictureinpicture,*leavepictureinpicture,!playsInline,poster,#width',
    ':svg:a^:svg:graphics|',
    ':svg:animate^:svg:animation|',
    ':svg:animateMotion^:svg:animation|',
    ':svg:animateTransform^:svg:animation|',
    ':svg:circle^:svg:geometry|',
    ':svg:clipPath^:svg:graphics|',
    ':svg:defs^:svg:graphics|',
    ':svg:desc^:svg:|',
    ':svg:discard^:svg:|',
    ':svg:ellipse^:svg:geometry|',
    ':svg:feBlend^:svg:|',
    ':svg:feColorMatrix^:svg:|',
    ':svg:feComponentTransfer^:svg:|',
    ':svg:feComposite^:svg:|',
    ':svg:feConvolveMatrix^:svg:|',
    ':svg:feDiffuseLighting^:svg:|',
    ':svg:feDisplacementMap^:svg:|',
    ':svg:feDistantLight^:svg:|',
    ':svg:feDropShadow^:svg:|',
    ':svg:feFlood^:svg:|',
    ':svg:feFuncA^:svg:componentTransferFunction|',
    ':svg:feFuncB^:svg:componentTransferFunction|',
    ':svg:feFuncG^:svg:componentTransferFunction|',
    ':svg:feFuncR^:svg:componentTransferFunction|',
    ':svg:feGaussianBlur^:svg:|',
    ':svg:feImage^:svg:|',
    ':svg:feMerge^:svg:|',
    ':svg:feMergeNode^:svg:|',
    ':svg:feMorphology^:svg:|',
    ':svg:feOffset^:svg:|',
    ':svg:fePointLight^:svg:|',
    ':svg:feSpecularLighting^:svg:|',
    ':svg:feSpotLight^:svg:|',
    ':svg:feTile^:svg:|',
    ':svg:feTurbulence^:svg:|',
    ':svg:filter^:svg:|',
    ':svg:foreignObject^:svg:graphics|',
    ':svg:g^:svg:graphics|',
    ':svg:image^:svg:graphics|decoding',
    ':svg:line^:svg:geometry|',
    ':svg:linearGradient^:svg:gradient|',
    ':svg:mpath^:svg:|',
    ':svg:marker^:svg:|',
    ':svg:mask^:svg:|',
    ':svg:metadata^:svg:|',
    ':svg:path^:svg:geometry|',
    ':svg:pattern^:svg:|',
    ':svg:polygon^:svg:geometry|',
    ':svg:polyline^:svg:geometry|',
    ':svg:radialGradient^:svg:gradient|',
    ':svg:rect^:svg:geometry|',
    ':svg:svg^:svg:graphics|#currentScale,#zoomAndPan',
    ':svg:script^:svg:|type',
    ':svg:set^:svg:animation|',
    ':svg:stop^:svg:|',
    ':svg:style^:svg:|!disabled,media,title,type',
    ':svg:switch^:svg:graphics|',
    ':svg:symbol^:svg:|',
    ':svg:tspan^:svg:textPositioning|',
    ':svg:text^:svg:textPositioning|',
    ':svg:textPath^:svg:textContent|',
    ':svg:title^:svg:|',
    ':svg:use^:svg:graphics|',
    ':svg:view^:svg:|#zoomAndPan',
    'data^[HTMLElement]|value',
    'keygen^[HTMLElement]|!autofocus,challenge,!disabled,form,keytype,name',
    'menuitem^[HTMLElement]|type,label,icon,!disabled,!checked,radiogroup,!default',
    'summary^[HTMLElement]|',
    'time^[HTMLElement]|dateTime',
    ':svg:cursor^:svg:|',
    ':math:^[HTMLElement]|!autofocus,nonce,*abort,*animationend,*animationiteration,*animationstart,*auxclick,*beforeinput,*beforematch,*beforetoggle,*beforexrselect,*blur,*cancel,*canplay,*canplaythrough,*change,*click,*close,*contentvisibilityautostatechange,*contextlost,*contextmenu,*contextrestored,*copy,*cuechange,*cut,*dblclick,*drag,*dragend,*dragenter,*dragleave,*dragover,*dragstart,*drop,*durationchange,*emptied,*ended,*error,*focus,*formdata,*gotpointercapture,*input,*invalid,*keydown,*keypress,*keyup,*load,*loadeddata,*loadedmetadata,*loadstart,*lostpointercapture,*mousedown,*mouseenter,*mouseleave,*mousemove,*mouseout,*mouseover,*mouseup,*mousewheel,*paste,*pause,*play,*playing,*pointercancel,*pointerdown,*pointerenter,*pointerleave,*pointermove,*pointerout,*pointerover,*pointerrawupdate,*pointerup,*progress,*ratechange,*reset,*resize,*scroll,*scrollend,*securitypolicyviolation,*seeked,*seeking,*select,*selectionchange,*selectstart,*slotchange,*stalled,*submit,*suspend,*timeupdate,*toggle,*transitioncancel,*transitionend,*transitionrun,*transitionstart,*volumechange,*waiting,*webkitanimationend,*webkitanimationiteration,*webkitanimationstart,*webkittransitionend,*wheel,%style,#tabIndex',
    ':math:math^:math:|',
    ':math:maction^:math:|',
    ':math:menclose^:math:|',
    ':math:merror^:math:|',
    ':math:mfenced^:math:|',
    ':math:mfrac^:math:|',
    ':math:mi^:math:|',
    ':math:mmultiscripts^:math:|',
    ':math:mn^:math:|',
    ':math:mo^:math:|',
    ':math:mover^:math:|',
    ':math:mpadded^:math:|',
    ':math:mphantom^:math:|',
    ':math:mroot^:math:|',
    ':math:mrow^:math:|',
    ':math:ms^:math:|',
    ':math:mspace^:math:|',
    ':math:msqrt^:math:|',
    ':math:mstyle^:math:|',
    ':math:msub^:math:|',
    ':math:msubsup^:math:|',
    ':math:msup^:math:|',
    ':math:mtable^:math:|',
    ':math:mtd^:math:|',
    ':math:mtext^:math:|',
    ':math:mtr^:math:|',
    ':math:munder^:math:|',
    ':math:munderover^:math:|',
    ':math:semantics^:math:|',
];
const _ATTR_TO_PROP = new Map(Object.entries({
    'class': 'className',
    'for': 'htmlFor',
    'formaction': 'formAction',
    'innerHtml': 'innerHTML',
    'readonly': 'readOnly',
    'tabindex': 'tabIndex',
}));
// Invert _ATTR_TO_PROP.
const _PROP_TO_ATTR = Array.from(_ATTR_TO_PROP).reduce((inverted, [propertyName, attributeName]) => {
    inverted.set(propertyName, attributeName);
    return inverted;
}, new Map());
export class DomElementSchemaRegistry extends ElementSchemaRegistry {
    constructor() {
        super();
        this._schema = new Map();
        // We don't allow binding to events for security reasons. Allowing event bindings would almost
        // certainly introduce bad XSS vulnerabilities. Instead, we store events in a separate schema.
        this._eventSchema = new Map;
        SCHEMA.forEach(encodedType => {
            const type = new Map();
            const events = new Set();
            const [strType, strProperties] = encodedType.split('|');
            const properties = strProperties.split(',');
            const [typeNames, superName] = strType.split('^');
            typeNames.split(',').forEach(tag => {
                this._schema.set(tag.toLowerCase(), type);
                this._eventSchema.set(tag.toLowerCase(), events);
            });
            const superType = superName && this._schema.get(superName.toLowerCase());
            if (superType) {
                for (const [prop, value] of superType) {
                    type.set(prop, value);
                }
                for (const superEvent of this._eventSchema.get(superName.toLowerCase())) {
                    events.add(superEvent);
                }
            }
            properties.forEach((property) => {
                if (property.length > 0) {
                    switch (property[0]) {
                        case '*':
                            events.add(property.substring(1));
                            break;
                        case '!':
                            type.set(property.substring(1), BOOLEAN);
                            break;
                        case '#':
                            type.set(property.substring(1), NUMBER);
                            break;
                        case '%':
                            type.set(property.substring(1), OBJECT);
                            break;
                        default:
                            type.set(property, STRING);
                    }
                }
            });
        });
    }
    hasProperty(tagName, propName, schemaMetas) {
        if (schemaMetas.some((schema) => schema.name === NO_ERRORS_SCHEMA.name)) {
            return true;
        }
        if (tagName.indexOf('-') > -1) {
            if (isNgContainer(tagName) || isNgContent(tagName)) {
                return false;
            }
            if (schemaMetas.some((schema) => schema.name === CUSTOM_ELEMENTS_SCHEMA.name)) {
                // Can't tell now as we don't know which properties a custom element will get
                // once it is instantiated
                return true;
            }
        }
        const elementProperties = this._schema.get(tagName.toLowerCase()) || this._schema.get('unknown');
        return elementProperties.has(propName);
    }
    hasElement(tagName, schemaMetas) {
        if (schemaMetas.some((schema) => schema.name === NO_ERRORS_SCHEMA.name)) {
            return true;
        }
        if (tagName.indexOf('-') > -1) {
            if (isNgContainer(tagName) || isNgContent(tagName)) {
                return true;
            }
            if (schemaMetas.some((schema) => schema.name === CUSTOM_ELEMENTS_SCHEMA.name)) {
                // Allow any custom elements
                return true;
            }
        }
        return this._schema.has(tagName.toLowerCase());
    }
    /**
     * securityContext returns the security context for the given property on the given DOM tag.
     *
     * Tag and property name are statically known and cannot change at runtime, i.e. it is not
     * possible to bind a value into a changing attribute or tag name.
     *
     * The filtering is based on a list of allowed tags|attributes. All attributes in the schema
     * above are assumed to have the 'NONE' security context, i.e. that they are safe inert
     * string values. Only specific well known attack vectors are assigned their appropriate context.
     */
    securityContext(tagName, propName, isAttribute) {
        if (isAttribute) {
            // NB: For security purposes, use the mapped property name, not the attribute name.
            propName = this.getMappedPropName(propName);
        }
        // Make sure comparisons are case insensitive, so that case differences between attribute and
        // property names do not have a security impact.
        tagName = tagName.toLowerCase();
        propName = propName.toLowerCase();
        let ctx = SECURITY_SCHEMA()[tagName + '|' + propName];
        if (ctx) {
            return ctx;
        }
        ctx = SECURITY_SCHEMA()['*|' + propName];
        return ctx ? ctx : SecurityContext.NONE;
    }
    getMappedPropName(propName) {
        return _ATTR_TO_PROP.get(propName) ?? propName;
    }
    getDefaultComponentElementName() {
        return 'ng-component';
    }
    validateProperty(name) {
        if (name.toLowerCase().startsWith('on')) {
            const msg = `Binding to event property '${name}' is disallowed for security reasons, ` +
                `please use (${name.slice(2)})=...` +
                `\nIf '${name}' is a directive input, make sure the directive is imported by the` +
                ` current module.`;
            return { error: true, msg: msg };
        }
        else {
            return { error: false };
        }
    }
    validateAttribute(name) {
        if (name.toLowerCase().startsWith('on')) {
            const msg = `Binding to event attribute '${name}' is disallowed for security reasons, ` +
                `please use (${name.slice(2)})=...`;
            return { error: true, msg: msg };
        }
        else {
            return { error: false };
        }
    }
    allKnownElementNames() {
        return Array.from(this._schema.keys());
    }
    allKnownAttributesOfElement(tagName) {
        const elementProperties = this._schema.get(tagName.toLowerCase()) || this._schema.get('unknown');
        // Convert properties to attributes.
        return Array.from(elementProperties.keys()).map(prop => _PROP_TO_ATTR.get(prop) ?? prop);
    }
    allKnownEventsOfElement(tagName) {
        return Array.from(this._eventSchema.get(tagName.toLowerCase()) ?? []);
    }
    normalizeAnimationStyleProperty(propName) {
        return dashCaseToCamelCase(propName);
    }
    normalizeAnimationStyleValue(camelCaseProp, userProvidedProp, val) {
        let unit = '';
        const strVal = val.toString().trim();
        let errorMsg = null;
        if (_isPixelDimensionStyle(camelCaseProp) && val !== 0 && val !== '0') {
            if (typeof val === 'number') {
                unit = 'px';
            }
            else {
                const valAndSuffixMatch = val.match(/^[+-]?[\d\.]+([a-z]*)$/);
                if (valAndSuffixMatch && valAndSuffixMatch[1].length == 0) {
                    errorMsg = `Please provide a CSS unit value for ${userProvidedProp}:${val}`;
                }
            }
        }
        return { error: errorMsg, value: strVal + unit };
    }
}
function _isPixelDimensionStyle(prop) {
    switch (prop) {
        case 'width':
        case 'height':
        case 'minWidth':
        case 'minHeight':
        case 'maxWidth':
        case 'maxHeight':
        case 'left':
        case 'top':
        case 'bottom':
        case 'right':
        case 'fontSize':
        case 'outlineWidth':
        case 'outlineOffset':
        case 'paddingTop':
        case 'paddingLeft':
        case 'paddingBottom':
        case 'paddingRight':
        case 'marginTop':
        case 'marginLeft':
        case 'marginBottom':
        case 'marginRight':
        case 'borderRadius':
        case 'borderWidth':
        case 'borderTopWidth':
        case 'borderLeftWidth':
        case 'borderRightWidth':
        case 'borderBottomWidth':
        case 'textIndent':
            return true;
        default:
            return false;
    }
}
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoiZG9tX2VsZW1lbnRfc2NoZW1hX3JlZ2lzdHJ5LmpzIiwic291cmNlUm9vdCI6IiIsInNvdXJjZXMiOlsiLi4vLi4vLi4vLi4vLi4vLi4vLi4vcGFja2FnZXMvY29tcGlsZXIvc3JjL3NjaGVtYS9kb21fZWxlbWVudF9zY2hlbWFfcmVnaXN0cnkudHMiXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6IkFBQUE7Ozs7OztHQU1HO0FBRUgsT0FBTyxFQUFDLHNCQUFzQixFQUFFLGdCQUFnQixFQUFrQixlQUFlLEVBQUMsTUFBTSxTQUFTLENBQUM7QUFDbEcsT0FBTyxFQUFDLGFBQWEsRUFBRSxXQUFXLEVBQUMsTUFBTSxtQkFBbUIsQ0FBQztBQUM3RCxPQUFPLEVBQUMsbUJBQW1CLEVBQUMsTUFBTSxTQUFTLENBQUM7QUFFNUMsT0FBTyxFQUFDLGVBQWUsRUFBQyxNQUFNLHVCQUF1QixDQUFDO0FBQ3RELE9BQU8sRUFBQyxxQkFBcUIsRUFBQyxNQUFNLDJCQUEyQixDQUFDO0FBRWhFLE1BQU0sT0FBTyxHQUFHLFNBQVMsQ0FBQztBQUMxQixNQUFNLE1BQU0sR0FBRyxRQUFRLENBQUM7QUFDeEIsTUFBTSxNQUFNLEdBQUcsUUFBUSxDQUFDO0FBQ3hCLE1BQU0sTUFBTSxHQUFHLFFBQVEsQ0FBQztBQUV4Qjs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7Ozs7R0F5Q0c7QUFFSCxvR0FBb0c7QUFDcEcsb0dBQW9HO0FBQ3BHLG9HQUFvRztBQUNwRyxvR0FBb0c7QUFDcEcsb0dBQW9HO0FBQ3BHLEVBQUU7QUFDRiwrRUFBK0U7QUFDL0UsRUFBRTtBQUNGLGtHQUFrRztBQUNsRyxxRUFBcUU7QUFDckUsRUFBRTtBQUNGLG9HQUFvRztBQUVwRyxNQUFNLE1BQU0sR0FFSjtJQUNFLHV3QkFBdXdCO1FBQ253Qiw4Q0FBOEM7UUFDOUMsa0tBQWtLO0lBQ3RLLHV2Q0FBdXZDO0lBQ3Z2Qyw4NkNBQTg2QztJQUM5NkMsK09BQStPO0lBQy9PLHlrQ0FBeWtDO0lBQ3pr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QUFnQixDQUFDO1FBQ3RCLEtBQUssaUJBQWlCLENBQUM7UUFDdkIsS0FBSyxrQkFBa0IsQ0FBQztRQUN4QixLQUFLLG1CQUFtQixDQUFDO1FBQ3pCLEtBQUssWUFBWTtZQUNmLE9BQU8sSUFBSSxDQUFDO1FBRWQ7WUFDRSxPQUFPLEtBQUssQ0FBQztJQUNqQixDQUFDO0FBQ0gsQ0FBQyIsInNvdXJjZXNDb250ZW50IjpbIi8qKlxuICogQGxpY2Vuc2VcbiAqIENvcHlyaWdodCBHb29nbGUgTExDIEFsbCBSaWdodHMgUmVzZXJ2ZWQuXG4gKlxuICogVXNlIG9mIHRoaXMgc291cmNlIGNvZGUgaXMgZ292ZXJuZWQgYnkgYW4gTUlULXN0eWxlIGxpY2Vuc2UgdGhhdCBjYW4gYmVcbiAqIGZvdW5kIGluIHRoZSBMSUNFTlNFIGZpbGUgYXQgaHR0cHM6Ly9hbmd1bGFyLmlvL2xpY2Vuc2VcbiAqL1xuXG5pbXBvcnQge0NVU1RPTV9FTEVNRU5UU19TQ0hFTUEsIE5PX0VSUk9SU19TQ0hFTUEsIFNjaGVtYU1ldGFkYXRhLCBTZWN1cml0eUNvbnRleHR9IGZyb20gJy4uL2NvcmUnO1xuaW1wb3J0IHtpc05nQ29udGFpbmVyLCBpc05nQ29udGVudH0gZnJvbSAnLi4vbWxfcGFyc2VyL3RhZ3MnO1xuaW1wb3J0IHtkYXNoQ2FzZVRvQ2FtZWxDYXNlfSBmcm9tICcuLi91dGlsJztcblxuaW1wb3J0IHtTRUNVUklUWV9TQ0hFTUF9IGZyb20gJy4vZG9tX3NlY3VyaXR5X3NjaGVtYSc7XG5pbXBvcnQge0VsZW1lbnRTY2hlbWFSZWdpc3RyeX0gZnJvbSAnLi9lbGVtZW50X3NjaGVtYV9yZWdpc3RyeSc7XG5cbmNvbnN0IEJPT0xFQU4gPSAnYm9vbGVhbic7XG5jb25zdCBOVU1CRVIgPSAnbnVtYmVyJztcbmNvbnN0IFNUUklORyA9ICdzdHJpbmcnO1xuY29uc3QgT0JKRUNUID0gJ29iamVjdCc7XG5cbi8qKlxuICogVGhpcyBhcnJheSByZXByZXNlbnRzIHRoZSBET00gc2NoZW1hLiBJdCBlbmNvZGVzIGluaGVyaXRhbmNlLCBwcm9wZXJ0aWVzLCBhbmQgZXZlbnRzLlxuICpcbiAqICMjIE92ZXJ2aWV3XG4gKlxuICogRWFjaCBsaW5lIHJlcHJlc2VudHMgb25lIGtpbmQgb2YgZWxlbWVudC4gVGhlIGBlbGVtZW50X2luaGVyaXRhbmNlYCBhbmQgcHJvcGVydGllcyBhcmUgam9pbmVkXG4gKiB1c2luZyBgZWxlbWVudF9pbmhlcml0YW5jZXxwcm9wZXJ0aWVzYCBzeW50YXguXG4gKlxuICogIyMgRWxlbWVudCBJbmhlcml0YW5jZVxuICpcbiAqIFRoZSBgZWxlbWVudF9pbmhlcml0YW5jZWAgY2FuIGJlIGZ1cnRoZXIgc3ViZGl2aWRlZCBhcyBgZWxlbWVudDEsZWxlbWVudDIsLi4uXnBhcmVudEVsZW1lbnRgLlxuICogSGVyZSB0aGUgaW5kaXZpZHVhbCBlbGVtZW50cyBhcmUgc2VwYXJhdGVkIGJ5IGAsYCAoY29tbWFzKS4gRXZlcnkgZWxlbWVudCBpbiB0aGUgbGlzdFxuICogaGFzIGlkZW50aWNhbCBwcm9wZXJ0aWVzLlxuICpcbiAqIEFuIGBlbGVtZW50YCBtYXkgaW5oZXJpdCBhZGRpdGlvbmFsIHByb3BlcnRpZXMgZnJvbSBgcGFyZW50RWxlbWVudGAgSWYgbm8gYF5wYXJlbnRFbGVtZW50YCBpc1xuICogc3BlY2lmaWVkIHRoZW4gYFwiXCJgIChibGFuaykgZWxlbWVudCBpcyBhc3N1bWVkLlxuICpcbiAqIE5PVEU6IFRoZSBibGFuayBlbGVtZW50IGluaGVyaXRzIGZyb20gcm9vdCBgW0VsZW1lbnRdYCBlbGVtZW50LCB0aGUgc3VwZXIgZWxlbWVudCBvZiBhbGxcbiAqIGVsZW1lbnRzLlxuICpcbiAqIE5PVEUgYW4gZWxlbWVudCBwcmVmaXggc3VjaCBhcyBgOnN2ZzpgIGhhcyBubyBzcGVjaWFsIG1lYW5pbmcgdG8gdGhlIHNjaGVtYS5cbiAqXG4gKiAjIyBQcm9wZXJ0aWVzXG4gKlxuICogRWFjaCBlbGVtZW50IGhhcyBhIHNldCBvZiBwcm9wZXJ0aWVzIHNlcGFyYXRlZCBieSBgLGAgKGNvbW1hcykuIEVhY2ggcHJvcGVydHkgY2FuIGJlIHByZWZpeGVkXG4gKiBieSBhIHNwZWNpYWwgY2hhcmFjdGVyIGRlc2lnbmF0aW5nIGl0cyB0eXBlOlxuICpcbiAqIC0gKG5vIHByZWZpeCk6IHByb3BlcnR5IGlzIGEgc3RyaW5nLlxuICogLSBgKmA6IHByb3BlcnR5IHJlcHJlc2VudHMgYW4gZXZlbnQuXG4gKiAtIGAhYDogcHJvcGVydHkgaXMgYSBib29sZWFuLlxuICogLSBgI2A6IHByb3BlcnR5IGlzIGEgbnVtYmVyLlxuICogLSBgJWA6IHByb3BlcnR5IGlzIGFuIG9iamVjdC5cbiAqXG4gKiAjIyBRdWVyeVxuICpcbiAqIFRoZSBjbGFzcyBjcmVhdGVzIGFuIGludGVybmFsIHNxdWFzIHJlcHJlc2VudGF0aW9uIHdoaWNoIGFsbG93cyB0byBlYXNpbHkgYW5zd2VyIHRoZSBxdWVyeSBvZlxuICogaWYgYSBnaXZlbiBwcm9wZXJ0eSBleGlzdCBvbiBhIGdpdmVuIGVsZW1lbnQuXG4gKlxuICogTk9URTogV2UgZG9uJ3QgeWV0IHN1cHBvcnQgcXVlcnlpbmcgZm9yIHR5cGVzIG9yIGV2ZW50cy5cbiAqIE5PVEU6IFRoaXMgc2NoZW1hIGlzIGF1dG8gZXh0cmFjdGVkIGZyb20gYHNjaGVtYV9leHRyYWN0b3IudHNgIGxvY2F0ZWQgaW4gdGhlIHRlc3QgZm9sZGVyLFxuICogICAgICAgc2VlIGRvbV9lbGVtZW50X3NjaGVtYV9yZWdpc3RyeV9zcGVjLnRzXG4gKi9cblxuLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PVxuLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PVxuLy8gPT09PT09PT09PT0gUyBUIE8gUCAgIC0gIFMgVCBPIFAgICAtICBTIFQgTyBQICAgLSAgUyBUIE8gUCAgIC0gIFMgVCBPIFAgICAtICBTIFQgTyBQICA9PT09PT09PT09PVxuLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PVxuLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PVxuLy9cbi8vICAgICAgICAgICAgICAgICAgICAgICBETyBOT1QgRURJVCBUSElTIERPTSBTQ0hFTUEgV0lUSE9VVCBBIFNFQ1VSSVRZIFJFVklFVyFcbi8vXG4vLyBOZXdseSBhZGRlZCBwcm9wZXJ0aWVzIG11c3QgYmUgc2VjdXJpdHkgcmV2aWV3ZWQgYW5kIGFzc2lnbmVkIGFuIGFwcHJvcHJpYXRlIFNlY3VyaXR5Q29udGV4dCBpblxuLy8gZG9tX3NlY3VyaXR5X3NjaGVtYS50cy4gUmVhY2ggb3V0IHRvIG1wcm9ic3QgJiByamFtZXQgZm9yIGRldGFpbHMuXG4vL1xuLy8gPT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PVxuXG5jb25zdCBTQ0hFTUE6XG4gICAgc3RyaW5nW10gPVxuICAgICAgICBbXG4gICAgICAgICAgJ1tFbGVtZW50XXx0ZXh0Q29udGVudCwlYXJpYUF0b21pYywlYXJpYUF1dG9Db21wbGV0ZSwlYXJpYUJ1c3ksJWFyaWFDaGVja2VkLCVhcmlhQ29sQ291bnQsJWFyaWFDb2xJbmRleCwlYXJpYUNvbFNwYW4sJWFyaWFDdXJyZW50LCVhcmlhRGVzY3JpcHRpb24sJWFyaWFEaXNhYmxlZCwlYXJpYUV4cGFuZGVkLCVhcmlhSGFzUG9wdXAsJWFyaWFIaWRkZW4sJWFyaWFLZXlTaG9ydGN1dHMsJWFyaWFMYWJlbCwlYXJpYUxldmVsLCVhcmlhTGl2ZSwlYXJpYU1vZGFsLCVhcmlhTXVsdGlMaW5lLCVhcmlhTXVsdGlTZWxlY3RhYmxlLCVhcmlhT3JpZW50YXRpb24sJWFyaWFQbGFjZWhvbGRlciwlYXJpYVBvc0luU2V0LCVhcmlhUHJlc3NlZCwlYXJpYVJlYWRPbmx5LCVhcmlhUmVsZXZhbnQsJWFyaWFSZXF1aXJlZCwlYXJpYVJvbGVEZXNjcmlwdGlvbiwlYXJpYVJvd0NvdW50LCVhcmlhUm93SW5kZXgsJWFyaWFSb3dTcGFuLCVhcmlhU2VsZWN0ZWQsJWFyaWFTZXRTaXplLCVhcmlhU29ydCwlYXJpYVZhbHVlTWF4LCVhcmlhVmFsdWVNaW4sJWFyaWFWYWx1ZU5vdywlYXJpYVZhbHVlVGV4dCwlY2xhc3NMaXN0LGNsYXNzTmFtZSxlbGVtZW50VGltaW5nLGlkLGlubmVySFRNTCwqYmVmb3JlY29weSwqYmVmb3JlY3V0LCpiZWZvcmVwYXN0ZSwqZnVsbHNjcmVlbmNoYW5nZSwqZnVsbHNjcmVlbmVycm9yLCpzZWFyY2gsKndlYmtpdGZ1bGxzY3JlZW5jaGFuZ2UsKndlYmtpdGZ1bGxzY3JlZW5lcnJvcixvdXRlckhUTUwsJXBhcnQsI3Njcm9sbExlZnQsI3Njcm9sbFRvcCxzbG90JyArXG4gICAgICAgICAgICAgIC8qIGFkZGVkIG1hbnVhbGx5IHRvIGF2b2lkIGJyZWFraW5nIGNoYW5nZXMgKi9cbiAgICAgICAgICAgICAgJywqbWVzc2FnZSwqbW96ZnVsbHNjcmVlbmNoYW5nZSwqbW96ZnVsbHNjcmVlbmVycm9yLCptb3pwb2ludGVybG9ja2NoYW5nZSwqbW96cG9pbnRlcmxvY2tlcnJvciwqd2ViZ2xjb250ZXh0Y3JlYXRpb25lcnJvciwqd2ViZ2xjb250ZXh0bG9zdCwqd2ViZ2xjb250ZXh0cmVzdG9yZWQnLFxuICAgICAgICAgICdbSFRNTEVsZW1lbnRdXltFbGVtZW50XXxhY2Nlc3NLZXksYXV0b2NhcGl0YWxpemUsIWF1dG9mb2N1cyxjb250ZW50RWRpdGFibGUsZGlyLCFkcmFnZ2FibGUsZW50ZXJLZXlIaW50LCFoaWRkZW4sIWluZXJ0LGlubmVyVGV4dCxpbnB1dE1vZGUsbGFuZyxub25jZSwqYWJvcnQsKmFuaW1hdGlvbmVuZCwqYW5pbWF0aW9uaXRlcmF0aW9uLCphbmltYXRpb25zdGFydCwqYXV4Y2xpY2ssKmJlZm9yZXhyc2VsZWN0LCpibHVyLCpjYW5jZWwsKmNhbnBsYXksKmNhbnBsYXl0aHJvdWdoLCpjaGFuZ2UsKmNsaWNrLCpjbG9zZSwqY29udGV4dG1lbnUsKmNvcHksKmN1ZWNoYW5nZSwqY3V0LCpkYmxjbGljaywqZHJhZywqZHJhZ2VuZCwqZHJhZ2VudGVyLCpkcmFnbGVhdmUsKmRyYWdvdmVyLCpkcmFnc3RhcnQsKmRyb3AsKmR1cmF0aW9uY2hhbmdlLCplbXB0aWVkLCplbmRlZCwqZXJyb3IsKmZvY3VzLCpmb3JtZGF0YSwqZ290cG9pbnRlcmNhcHR1cmUsKmlucHV0LCppbnZhbGlkLCprZXlkb3duLCprZXlwcmVzcywqa2V5dXAsKmxvYWQsKmxvYWRlZGRhdGEsKmxvYWRlZG1ldGFkYXRhLCpsb2Fkc3RhcnQsKmxvc3Rwb2ludGVyY2FwdHVyZSwqbW91c2Vkb3duLCptb3VzZWVudGVyLCptb3VzZWxlYXZlLCptb3VzZW1vdmUsKm1vdXNlb3V0LCptb3VzZW92ZXIsKm1vdXNldXAsKm1vdXNld2hlZWwsKnBhc3RlLCpwYXVzZSwqcGxheSwqcGxheWluZywqcG9pbnRlcmNhbmNlbCwqcG9pbnRlcmRvd24sKnBvaW50ZXJlbnRlciwqcG9pbnRlcmxlYXZlLCpwb2ludGVybW92ZSwqcG9pbnRlcm91dCwqcG9pbnRlcm92ZXIsKnBvaW50ZXJyYXd1cGRhdGUsKnBvaW50ZXJ1cCwqcHJvZ3Jlc3MsKnJhdGVjaGFuZ2UsKnJlc2V0LCpyZXNpemUsKnNjcm9sbCwqc2VjdXJpdHlwb2xpY3l2aW9sYXRpb24sKnNlZWtlZCwqc2Vla2luZywqc2VsZWN0LCpzZWxlY3Rpb25jaGFuZ2UsKnNlbGVjdHN0YXJ0LCpzbG90Y2hhbmdlLCpzdGFsbGVkLCpzdWJtaXQsKnN1c3BlbmQsKnRpbWV1cGRhdGUsKnRvZ2dsZSwqdHJhbnNpdGlvbmNhbmNlbCwqdHJhbnNpdGlvbmVuZCwqdHJhbnNpdGlvbnJ1biwqdHJhbnNpdGlvbnN0YXJ0LCp2b2x1bWVjaGFuZ2UsKndhaXRpbmcsKndlYmtpdGFuaW1hdGlvbmVuZCwqd2Via2l0YW5pbWF0aW9uaXRlcmF0aW9uLCp3ZWJraXRhbmltYXRpb25zdGFydCwqd2Via2l0dHJhbnNpdGlvbmVuZCwqd2hlZWwsb3V0ZXJUZXh0LCFzcGVsbGNoZWNrLCVzdHlsZSwjdGFiSW5kZXgsdGl0bGUsIXRyYW5zbGF0ZSx2aXJ0dWFsS2V5Ym9hcmRQb2xpY3knLFxuICAgICAgICAgICdhYmJyLGFkZHJlc3MsYXJ0aWNsZSxhc2lkZSxiLGJkaSxiZG8sY2l0ZSxjb250ZW50LGNvZGUsZGQsZGZuLGR0LGVtLGZpZ2NhcHRpb24sZmlndXJlLGZvb3RlcixoZWFkZXIsaGdyb3VwLGksa2JkLG1haW4sbWFyayxuYXYsbm9zY3JpcHQscmIscnAscnQscnRjLHJ1YnkscyxzYW1wLHNlY3Rpb24sc21hbGwsc3Ryb25nLHN1YixzdXAsdSx2YXIsd2JyXltIVE1MRWxlbWVudF18YWNjZXNzS2V5LGF1dG9jYXBpdGFsaXplLCFhdXRvZm9jdXMsY29udGVudEVkaXRhYmxlLGRpciwhZHJhZ2dhYmxlLGVudGVyS2V5SGludCwhaGlkZGVuLGlubmVyVGV4dCxpbnB1dE1vZGUsbGFuZyxub25jZSwqYWJvcnQsKmFuaW1hdGlvbmVuZCwqYW5pbWF0aW9uaXRlcmF0aW9uLCphbmltYXRpb25zdGFydCwqYXV4Y2xpY2ssKmJlZm9yZXhyc2VsZWN0LCpibHVyLCpjYW5jZWwsKmNhbnBsYXksKmNhbnBsYXl0aHJvdWdoLCpjaGFuZ2UsKmNsaWNrLCpjbG9zZSwqY29udGV4dG1lbnUsKmNvcHksKmN1ZWNoYW5nZSwqY3V0LCpkYmxjbGljaywqZHJhZywqZHJhZ2VuZCwqZHJhZ2VudGVyLCpkcmFnbGVhdmUsKmRyYWdvdmVyLCpkcmFnc3RhcnQsKmRyb3AsKmR1cmF0aW9uY2hhbmdlLCplbXB0aWVkLCplbmRlZCwqZXJyb3IsKmZvY3VzLCpmb3JtZGF0YSwqZ290cG9pbnRlcmNhcHR1cmUsKmlucHV0LCppbnZhbGlkLCprZXlkb3duLCprZXlwcmVzcywqa2V5dXAsKmxvYWQsKmxvYWRlZGRhdGEsKmxvYWRlZG1ldGFkYXRhLCpsb2Fkc3RhcnQsKmxvc3Rwb2ludGVyY2FwdHVyZSwqbW91c2Vkb3duLCptb3VzZWVudGVyLCptb3VzZWxlYXZlLCptb3VzZW1vdmUsKm1vdXNlb3V0LCptb3VzZW92ZXIsKm1vdXNldXAsKm1vdXNld2hlZWwsKnBhc3RlLCpwYXVzZSwqcGxheSwqcGxheWluZywqcG9pbnRlcmNhbmNlbCwqcG9pbnRlcmRvd24sKnBvaW50ZXJlbnRlciwqcG9pbnRlcmxlYXZlLCpwb2ludGVybW92ZSwqcG9pbnRlcm91dCwqcG9pbnRlcm92ZXIsKnBvaW50ZXJyYXd1cGRhdGUsKnBvaW50ZXJ1cCwqcHJvZ3Jlc3MsKnJhdGVjaGFuZ2UsKnJlc2V0LCpyZXNpemUsKnNjcm9sbCwqc2VjdXJpdHlwb2xpY3l2aW9sYXRpb24sKnNlZWtlZCwqc2Vla2luZywqc2VsZWN0LCpzZWxlY3Rpb25jaGFuZ2UsKnNlbGVjdHN0YXJ0LCpzbG90Y2hhbmdlLCpzdGFsbGVkLCpzdWJtaXQsKnN1c3BlbmQsKnRpbWV1cGRhdGUsKnRvZ2dsZSwqdHJhbnNpdGlvbmNhbmNlbCwqdHJhbnNpdGlvbmVuZCwqdHJhbnNpdGlvbnJ1biwqdHJhbnNpdGlvbnN0YXJ0LCp2b2x1bWVjaGFuZ2UsKndhaXRpbmcsKndlYmtpdGFuaW1hdGlvbmVuZCwqd2Via2l0YW5pbWF0aW9uaXRlcmF0aW9uLCp3ZWJraXRhbmltYXRpb25zdGFydCwqd2Via2l0dHJhbnNpdGlvbmVuZCwqd2hlZWwsb3V0ZXJUZXh0LCFzcGVsbGNoZWNrLCVzdHlsZSwjdGFiSW5kZXgsdGl0bGUsIXRyYW5zbGF0ZSx2aXJ0dWFsS2V5Ym9hcmRQb2xpY3knLFxuICAgICAgICAgICdtZWRpYV5bSFRNTEVsZW1lbnRdfCFhdXRvcGxheSwhY29udHJvbHMsJWNvbnRyb2xzTGlzdCwlY3Jvc3NPcmlnaW4sI2N1cnJlbnRUaW1lLCFkZWZhdWx0TXV0ZWQsI2RlZmF1bHRQbGF5YmFja1JhdGUsIWRpc2FibGVSZW1vdGVQbGF5YmFjaywhbG9vcCwhbXV0ZWQsKmVuY3J5cHRlZCwqd2FpdGluZ2ZvcmtleSwjcGxheWJhY2tSYXRlLHByZWxvYWQsIXByZXNlcnZlc1BpdGNoLHNyYywlc3JjT2JqZWN0LCN2b2x1bWUnLFxuICAgICAgICAgICc6c3ZnOl5bSFRNTEVsZW1lbnRdfCFhdXRvZm9jdXMsbm9uY2UsKmFib3J0LCphbmltYXRpb25lbmQsKmFuaW1hdGlvbml0ZXJhdGlvbiwqYW5pbWF0aW9uc3RhcnQsKmF1eGNsaWNrLCpiZWZvcmV4cnNlbGVjdCwqYmx1ciwqY2FuY2VsLCpjYW5wbGF5LCpjYW5wbGF5dGhyb3VnaCwqY2hhbmdlLCpjbGljaywqY2xvc2UsKmNvbnRleHRtZW51LCpjb3B5LCpjdWVjaGFuZ2UsKmN1dCwqZGJsY2xpY2ssKmRyYWcsKmRyYWdlbmQsKmRyYWdlbnRlciwqZHJhZ2xlYXZlLCpkcmFnb3ZlciwqZHJhZ3N0YXJ0LCpkcm9wLCpkdXJhdGlvbmNoYW5nZSwqZW1wdGllZCwqZW5kZWQsKmVycm9yLCpmb2N1cywqZm9ybWRhdGEsKmdvdHBvaW50ZXJjYXB0dXJlLCppbnB1dCwqaW52YWxpZCwqa2V5ZG93biwqa2V5cHJlc3MsKmtleXVwLCpsb2FkLCpsb2FkZWRkYXRhLCpsb2FkZWRtZXRhZGF0YSwqbG9hZHN0YXJ0LCpsb3N0cG9pbnRlcmNhcHR1cmUsKm1vdXNlZG93biwqbW91c2VlbnRlciwqbW91c2VsZWF2ZSwqbW91c2Vtb3ZlLCptb3VzZW91dCwqbW91c2VvdmVyLCptb3VzZXVwLCptb3VzZXdoZWVsLCpwYXN0ZSwqcGF1c2UsKnBsYXksKnBsYXlpbmcsKnBvaW50ZXJjYW5jZWwsKnBvaW50ZXJkb3duLCpwb2ludGVyZW50ZXIsKnBvaW50ZXJsZWF2ZSwqcG9pbnRlcm1vdmUsKnBvaW50ZXJvdXQsKnBvaW50ZXJvdmVyLCpwb2ludGVycmF3dXBkYXRlLCpwb2ludGVydXAsKnByb2dyZXNzLCpyYXRlY2hhbmdlLCpyZXNldCwqcmVzaXplLCpzY3JvbGwsKnNlY3VyaXR5cG9saWN5dmlvbGF0aW9uLCpzZWVrZWQsKnNlZWtpbmcsKnNlbGVjdCwqc2VsZWN0aW9uY2hhbmdlLCpzZWxlY3RzdGFydCwqc2xvdGNoYW5nZSwqc3RhbGxlZCwqc3VibWl0LCpzdXNwZW5kLCp0aW1ldXBkYXRlLCp0b2dnbGUsKnRyYW5zaXRpb25jYW5jZWwsKnRyYW5zaXRpb25lbmQsKnRyYW5zaXRpb25ydW4sKnRyYW5zaXRpb25zdGFydCwqdm9sdW1lY2hhbmdlLCp3YWl0aW5nLCp3ZWJraXRhbmltYXRpb25lbmQsKndlYmtpdGFuaW1hdGlvbml0ZXJhdGlvbiwqd2Via2l0YW5pbWF0aW9uc3RhcnQsKndlYmtpdHRyYW5zaXRpb25lbmQsKndoZWVsLCVzdHlsZSwjdGFiSW5kZXgnLFxuICAgICAgICAgICc6c3ZnOmdyYXBoaWNzXjpzdmc6fCcsXG4gICAgICAgICAgJzpzdmc6YW5pbWF0aW9uXjpzdmc6fCpiZWdpbiwqZW5kLCpyZXBlYXQnLFxuICAgICAgICAgICc6c3ZnOmdlb21ldHJ5Xjpzdmc6fCcsXG4gICAgICAgICAgJzpzdmc6Y29tcG9uZW50VHJhbnNmZXJGdW5jdGlvbl46c3ZnOnwnLFxuICAgICAgICAgICc6c3ZnOmdyYWRpZW50Xjpzdmc6fCcsXG4gICAgICAgICAgJzpzdmc6dGV4dENvbnRlbnReOnN2ZzpncmFwaGljc3wnLFxuICAgICAgICAgICc6c3ZnOnRleHRQb3NpdGlvbmluZ146c3ZnOnRleHRDb250ZW50fCcsXG4gICAgICAgICAgJ2FeW0hUTUxFbGVtZW50XXxjaGFyc2V0LGNvb3Jkcyxkb3dubG9hZCxoYXNoLGhvc3QsaG9zdG5hbWUsaHJlZixocmVmbGFuZyxuYW1lLHBhc3N3b3JkLHBhdGhuYW1lLHBpbmcscG9ydCxwcm90b2NvbCxyZWZlcnJlclBvbGljeSxyZWwsJXJlbExpc3QscmV2LHNlYXJjaCxzaGFwZSx0YXJnZXQsdGV4dCx0eXBlLHVzZXJuYW1lJyxcbiAgICAgICAgICAnYXJlYV5bSFRNTEVsZW1lbnRdfGFsdCxjb29yZHMsZG93bmxvYWQsaGFzaCxob3N0LGhvc3RuYW1lLGhyZWYsIW5vSHJlZixwYXNzd29yZCxwYXRobmFtZSxwaW5nLHBvcnQscHJvdG9jb2wscmVmZXJyZXJQb2xpY3kscmVsLCVyZWxMaXN0LHNlYXJjaCxzaGFwZSx0YXJnZXQsdXNlcm5hbWUnLFxuICAgICAgICAgICdhdWRpb15tZWRpYXwnLFxuICAgICAgICAgICdicl5bSFRNTEVsZW1lbnRdfGNsZWFyJyxcbiAgICAgICAgICAnYmFzZV5bSFRNTEVsZW1lbnRdfGhyZWYsdGFyZ2V0JyxcbiAgICAgICAgICAnYm9keV5bSFRNTEVsZW1lbnRdfGFMaW5rLGJhY2tncm91bmQsYmdDb2xvcixsaW5rLCphZnRlcnByaW50LCpiZWZvcmVwcmludCwqYmVmb3JldW5sb2FkLCpibHVyLCplcnJvciwqZm9jdXMsKmhhc2hjaGFuZ2UsKmxhbmd1YWdlY2hhbmdlLCpsb2FkLCptZXNzYWdlLCptZXNzYWdlZXJyb3IsKm9mZmxpbmUsKm9ubGluZSwqcGFnZWhpZGUsKnBhZ2VzaG93LCpwb3BzdGF0ZSwqcmVqZWN0aW9uaGFuZGxlZCwqcmVzaXplLCpzY3JvbGwsKnN0b3JhZ2UsKnVuaGFuZGxlZHJlamVjdGlvbiwqdW5sb2FkLHRleHQsdkxpbmsnLFxuICAgICAgICAgICdidXR0b25eW0hUTUxFbGVtZW50XXwhZGlzYWJsZWQsZm9ybUFjdGlvbixmb3JtRW5jdHlwZSxmb3JtTWV0aG9kLCFmb3JtTm9WYWxpZGF0ZSxmb3JtVGFyZ2V0LG5hbWUsdHlwZSx2YWx1ZScsXG4gICAgICAgICAgJ2NhbnZhc15bSFRNTEVsZW1lbnRdfCNoZWlnaHQsI3dpZHRoJyxcbiAgICAgICAgICAnY29udGVudF5bSFRNTEVsZW1lbnRdfHNlbGVjdCcsXG4gICAgICAgICAgJ2RsXltIVE1MRWxlbWVudF18IWNvbXBhY3QnLFxuICAgICAgICAgICdkYXRhXltIVE1MRWxlbWVudF18dmFsdWUnLFxuICAgICAgICAgICdkYXRhbGlzdF5bSFRNTEVsZW1lbnRdfCcsXG4gICAgICAgICAgJ2RldGFpbHNeW0hUTUxFbGVtZW50XXwhb3BlbicsXG4gICAgICAgICAgJ2RpYWxvZ15bSFRNTEVsZW1lbnRdfCFvcGVuLHJldHVyblZhbHVlJyxcbiAgICAgICAgICAnZGlyXltIVE1MRWxlbWVudF18IWNvbXBhY3QnLFxuICAgICAgICAgICdkaXZeW0hUTUxFbGVtZW50XXxhbGlnbicsXG4gICAgICAgICAgJ2VtYmVkXltIVE1MRWxlbWVudF18YWxpZ24saGVpZ2h0LG5hbWUsc3JjLHR5cGUsd2lkdGgnLFxuICAgICAgICAgICdmaWVsZHNldF5bSFRNTEVsZW1lbnRdfCFkaXNhYmxlZCxuYW1lJyxcbiAgICAgICAgICAnZm9udF5bSFRNTEVsZW1lbnRdfGNvbG9yLGZhY2Usc2l6ZScsXG4gICAgICAgICAgJ2Zvcm1eW0hUTUxFbGVtZW50XXxhY2NlcHRDaGFyc2V0LGFjdGlvbixhdXRvY29tcGxldGUsZW5jb2RpbmcsZW5jdHlwZSxtZXRob2QsbmFtZSwhbm9WYWxpZGF0ZSx0YXJnZXQnLFxuICAgICAgICAgICdmcmFtZV5bSFRNTEVsZW1lbnRdfGZyYW1lQm9yZGVyLGxvbmdEZXNjLG1hcmdpbkhlaWdodCxtYXJnaW5XaWR0aCxuYW1lLCFub1Jlc2l6ZSxzY3JvbGxpbmcsc3JjJyxcbiAgICAgICAgICAnZnJhbWVzZXReW0hUTUxFbGVtZW50XXxjb2xzLCphZnRlcnByaW50LCpiZWZvcmVwcmludCwqYmVmb3JldW5sb2FkLCpibHVyLCplcnJvciwqZm9jdXMsKmhhc2hjaGFuZ2UsKmxhbmd1YWdlY2hhbmdlLCpsb2FkLCptZXNzYWdlLCptZXNzYWdlZXJyb3IsKm9mZmxpbmUsKm9ubGluZSwqcGFnZWhpZGUsKnBhZ2VzaG93LCpwb3BzdGF0ZSwqcmVqZWN0aW9uaGFuZGxlZCwqcmVzaXplLCpzY3JvbGwsKnN0b3JhZ2UsKnVuaGFuZGxlZHJlamVjdGlvbiwqdW5sb2FkLHJvd3MnLFxuICAgICAgICAgICdocl5bSFRNTEVsZW1lbnRdfGFsaWduLGNvbG9yLCFub1NoYWRlLHNpemUsd2lkdGgnLFxuICAgICAgICAgICdoZWFkXltIVE1MRWxlbWVudF18JyxcbiAgICAgICAgICAnaDEsaDIsaDMsaDQsaDUsaDZeW0hUTUxFbGVtZW50XXxhbGlnbicsXG4gICAgICAgICAgJ2h0bWxeW0hUTUxFbGVtZW50XXx2ZXJzaW9uJyxcbiAgICAgICAgICAnaWZyYW1lXltIVE1MRWxlbWVudF18YWxpZ24sYWxsb3csIWFsbG93RnVsbHNjcmVlbiwhYWxsb3dQYXltZW50UmVxdWVzdCxjc3AsZnJhbWVCb3JkZXIsaGVpZ2h0LGxvYWRpbmcsbG9uZ0Rlc2MsbWFyZ2luSGVpZ2h0LG1hcmdpbldpZHRoLG5hbWUscmVmZXJyZXJQb2xpY3ksJXNhbmRib3gsc2Nyb2xsaW5nLHNyYyxzcmNkb2Msd2lkdGgnLFxuICAgICAgICAgICdpbWdeW0hUTUxFbGVtZW50XXxhbGlnbixhbHQsYm9yZGVyLCVjcm9zc09yaWdpbixkZWNvZGluZywjaGVpZ2h0LCNoc3BhY2UsIWlzTWFwLGxvYWRpbmcsbG9uZ0Rlc2MsbG93c3JjLG5hbWUscmVmZXJyZXJQb2xpY3ksc2l6ZXMsc3JjLHNyY3NldCx1c2VNYXAsI3ZzcGFjZSwjd2lkdGgnLFxuICAgICAgICAgICdpbnB1dF5bSFRNTEVsZW1lbnRdfGFjY2VwdCxhbGlnbixhbHQsYXV0b2NvbXBsZXRlLCFjaGVja2VkLCFkZWZhdWx0Q2hlY2tlZCxkZWZhdWx0VmFsdWUsZGlyTmFtZSwhZGlzYWJsZWQsJWZpbGVzLGZvcm1BY3Rpb24sZm9ybUVuY3R5cGUsZm9ybU1ldGhvZCwhZm9ybU5vVmFsaWRhdGUsZm9ybVRhcmdldCwjaGVpZ2h0LCFpbmNyZW1lbnRhbCwhaW5kZXRlcm1pbmF0ZSxtYXgsI21heExlbmd0aCxtaW4sI21pbkxlbmd0aCwhbXVsdGlwbGUsbmFtZSxwYXR0ZXJuLHBsYWNlaG9sZGVyLCFyZWFkT25seSwhcmVxdWlyZWQsc2VsZWN0aW9uRGlyZWN0aW9uLCNzZWxlY3Rpb25FbmQsI3NlbGVjdGlvblN0YXJ0LCNzaXplLHNyYyxzdGVwLHR5cGUsdXNlTWFwLHZhbHVlLCV2YWx1ZUFzRGF0ZSwjdmFsdWVBc051bWJlciwjd2lkdGgnLFxuICAgICAgICAgICdsaV5bSFRNTEVsZW1lbnRdfHR5cGUsI3ZhbHVlJyxcbiAgICAgICAgICAnbGFiZWxeW0hUTUxFbGVtZW50XXxodG1sRm9yJyxcbiAgICAgICAgICAnbGVnZW5kXltIVE1MRWxlbWVudF18YWxpZ24nLFxuICAgICAgICAgICdsaW5rXltIVE1MRWxlbWVudF18YXMsY2hhcnNldCwlY3Jvc3NPcmlnaW4sIWRpc2FibGVkLGhyZWYsaHJlZmxhbmcsaW1hZ2VTaXplcyxpbWFnZVNyY3NldCxpbnRlZ3JpdHksbWVkaWEscmVmZXJyZXJQb2xpY3kscmVsLCVyZWxMaXN0LHJldiwlc2l6ZXMsdGFyZ2V0LHR5cGUnLFxuICAgICAgICAgICdtYXBeW0hUTUxFbGVtZW50XXxuYW1lJyxcbiAgICAgICAgICAnbWFycXVlZV5bSFRNTEVsZW1lbnRdfGJlaGF2aW9yLGJnQ29sb3IsZGlyZWN0aW9uLGhlaWdodCwjaHNwYWNlLCNsb29wLCNzY3JvbGxBbW91bnQsI3Njcm9sbERlbGF5LCF0cnVlU3BlZWQsI3ZzcGFjZSx3aWR0aCcsXG4gICAgICAgICAgJ21lbnVeW0hUTUxFbGVtZW50XXwhY29tcGFjdCcsXG4gICAgICAgICAgJ21ldGFeW0hUTUxFbGVtZW50XXxjb250ZW50LGh0dHBFcXVpdixtZWRpYSxuYW1lLHNjaGVtZScsXG4gICAgICAgICAgJ21ldGVyXltIVE1MRWxlbWVudF18I2hpZ2gsI2xvdywjbWF4LCNtaW4sI29wdGltdW0sI3ZhbHVlJyxcbiAgICAgICAgICAnaW5zLGRlbF5bSFRNTEVsZW1lbnRdfGNpdGUsZGF0ZVRpbWUnLFxuICAgICAgICAgICdvbF5bSFRNTEVsZW1lbnRdfCFjb21wYWN0LCFyZXZlcnNlZCwjc3RhcnQsdHlwZScsXG4gICAgICAgICAgJ29iamVjdF5bSFRNTEVsZW1lbnRdfGFsaWduLGFyY2hpdmUsYm9yZGVyLGNvZGUsY29kZUJhc2UsY29kZVR5cGUsZGF0YSwhZGVjbGFyZSxoZWlnaHQsI2hzcGFjZSxuYW1lLHN0YW5kYnksdHlwZSx1c2VNYXAsI3ZzcGFjZSx3aWR0aCcsXG4gICAgICAgICAgJ29wdGdyb3VwXltIVE1MRWxlbWVudF18IWRpc2FibGVkLGxhYmVsJyxcbiAgICAgICAgICAnb3B0aW9uXltIVE1MRWxlbWVudF18IWRlZmF1bHRTZWxlY3RlZCwhZGlzYWJsZWQsbGFiZWwsIXNlbGVjdGVkLHRleHQsdmFsdWUnLFxuICAgICAgICAgICdvdXRwdXReW0hUTUxFbGVtZW50XXxkZWZhdWx0VmFsdWUsJWh0bWxGb3IsbmFtZSx2YWx1ZScsXG4gICAgICAgICAgJ3BeW0hUTUxFbGVtZW50XXxhbGlnbicsXG4gICAgICAgICAgJ3BhcmFtXltIVE1MRWxlbWVudF18bmFtZSx0eXBlLHZhbHVlLHZhbHVlVHlwZScsXG4gICAgICAgICAgJ3BpY3R1cmVeW0hUTUxFbGVtZW50XXwnLFxuICAgICAgICAgICdwcmVeW0hUTUxFbGVtZW50XXwjd2lkdGgnLFxuICAgICAgICAgICdwcm9ncmVzc15bSFRNTEVsZW1lbnRdfCNtYXgsI3ZhbHVlJyxcbiAgICAgICAgICAncSxibG9ja3F1b3RlLGNpdGVeW0hUTUxFbGVtZW50XXwnLFxuICAgICAgICAgICdzY3JpcHReW0hUTUxFbGVtZW50XXwhYXN5bmMsY2hhcnNldCwlY3Jvc3NPcmlnaW4sIWRlZmVyLGV2ZW50LGh0bWxGb3IsaW50ZWdyaXR5LCFub01vZHVsZSwlcmVmZXJyZXJQb2xpY3ksc3JjLHRleHQsdHlwZScsXG4gICAgICAgICAgJ3NlbGVjdF5bSFRNTEVsZW1lbnRdfGF1dG9jb21wbGV0ZSwhZGlzYWJsZWQsI2xlbmd0aCwhbXVsdGlwbGUsbmFtZSwhcmVxdWlyZWQsI3NlbGVjdGVkSW5kZXgsI3NpemUsdmFsdWUnLFxuICAgICAgICAgICdzbG90XltIVE1MRWxlbWVudF18bmFtZScsXG4gICAgICAgICAgJ3NvdXJjZV5bSFRNTEVsZW1lbnRdfCNoZWlnaHQsbWVkaWEsc2l6ZXMsc3JjLHNyY3NldCx0eXBlLCN3aWR0aCcsXG4gICAgICAgICAgJ3NwYW5eW0hUTUxFbGVtZW50XXwnLFxuICAgICAgICAgICdzdHlsZV5bSFRNTEVsZW1lbnRdfCFkaXNhYmxlZCxtZWRpYSx0eXBlJyxcbiAgICAgICAgICAnY2FwdGlvbl5bSFRNTEVsZW1lbnRdfGFsaWduJyxcbiAgICAgICAgICAndGgsdGReW0hUTUxFbGVtZW50XXxhYmJyLGFsaWduLGF4aXMsYmdDb2xvcixjaCxjaE9mZiwjY29sU3BhbixoZWFkZXJzLGhlaWdodCwhbm9XcmFwLCNyb3dTcGFuLHNjb3BlLHZBbGlnbix3aWR0aCcsXG4gICAgICAgICAgJ2NvbCxjb2xncm91cF5bSFRNTEVsZW1lbnRdfGFsaWduLGNoLGNoT2ZmLCNzcGFuLHZBbGlnbix3aWR0aCcsXG4gICAgICAgICAgJ3RhYmxlXltIVE1MRWxlbWVudF18YWxpZ24sYmdDb2xvcixib3JkZXIsJWNhcHRpb24sY2VsbFBhZGRpbmcsY2VsbFNwYWNpbmcsZnJhbWUscnVsZXMsc3VtbWFyeSwldEZvb3QsJXRIZWFkLHdpZHRoJyxcbiAgICAgICAgICAndHJeW0hUTUxFbGVtZW50XXxhbGlnbixiZ0NvbG9yLGNoLGNoT2ZmLHZBbGlnbicsXG4gICAgICAgICAgJ3Rmb290LHRoZWFkLHRib2R5XltIVE1MRWxlbWVudF18YWxpZ24sY2gsY2hPZmYsdkFsaWduJyxcbiAgICAgICAgICAndGVtcGxhdGVeW0hUTUxFbGVtZW50XXwnLFxuICAgICAgICAgICd0ZXh0YXJlYV5bSFRNTEVsZW1lbnRdfGF1dG9jb21wbGV0ZSwjY29scyxkZWZhdWx0VmFsdWUsZGlyTmFtZSwhZGlzYWJsZWQsI21heExlbmd0aCwjbWluTGVuZ3RoLG5hbWUscGxhY2Vob2xkZXIsIXJlYWRPbmx5LCFyZXF1aXJlZCwjcm93cyxzZWxlY3Rpb25EaXJlY3Rpb24sI3NlbGVjdGlvbkVuZCwjc2VsZWN0aW9uU3RhcnQsdmFsdWUsd3JhcCcsXG4gICAgICAgICAgJ3RpbWVeW0hUTUxFbGVtZW50XXxkYXRlVGltZScsXG4gICAgICAgICAgJ3RpdGxlXltIVE1MRWxlbWVudF18dGV4dCcsXG4gICAgICAgICAgJ3RyYWNrXltIVE1MRWxlbWVudF18IWRlZmF1bHQsa2luZCxsYWJlbCxzcmMsc3JjbGFuZycsXG4gICAgICAgICAgJ3VsXltIVE1MRWxlbWVudF18IWNvbXBhY3QsdHlwZScsXG4gICAgICAgICAgJ3Vua25vd25eW0hUTUxFbGVtZW50XXwnLFxuICAgICAgICAgICd2aWRlb15tZWRpYXwhZGlzYWJsZVBpY3R1cmVJblBpY3R1cmUsI2hlaWdodCwqZW50ZXJwaWN0dXJlaW5waWN0dXJlLCpsZWF2ZXBpY3R1cmVpbnBpY3R1cmUsIXBsYXlzSW5saW5lLHBvc3Rlciwjd2lkdGgnLFxuICAgICAgICAgICc6c3ZnOmFeOnN2ZzpncmFwaGljc3wnLFxuICAgICAgICAgICc6c3ZnOmFuaW1hdGVeOnN2ZzphbmltYXRpb258JyxcbiAgICAgICAgICAnOnN2ZzphbmltYXRlTW90aW9uXjpzdmc6YW5pbWF0aW9ufCcsXG4gICAgICAgICAgJzpzdmc6YW5pbWF0ZVRyYW5zZm9ybV46c3ZnOmFuaW1hdGlvbnwnLFxuICAgICAgICAgICc6c3ZnOmNpcmNsZV46c3ZnOmdlb21ldHJ5fCcsXG4gICAgICAgICAgJzpzdmc6Y2xpcFBhdGheOnN2ZzpncmFwaGljc3wnLFxuICAgICAgICAgICc6c3ZnOmRlZnNeOnN2ZzpncmFwaGljc3wnLFxuICAgICAgICAgICc6c3ZnOmRlc2NeOnN2Zzp8JyxcbiAgICAgICAgICAnOnN2ZzpkaXNjYXJkXjpzdmc6fCcsXG4gICAgICAgICAgJzpzdmc6ZWxsaXBzZV46c3ZnOmdlb21ldHJ5fCcsXG4gICAgICAgICAgJzpzdmc6ZmVCbGVuZF46c3ZnOnwnLFxuICAgICAgICAgICc6c3ZnOmZlQ29sb3JNYXRyaXheOnN2Zzp8JyxcbiAgICAgICAgICAnOnN2ZzpmZUNvbXBvbmVudFRyYW5zZmVyXjpzdmc6fCcsXG4gICAgICAgICAgJzpzdmc6ZmVDb21wb3NpdGVeOnN2Zzp8JyxcbiAgICAgICAgICAnOnN2ZzpmZUNvbnZvbHZlTWF0cml4Xjpzdmc6fCcsXG4gICAgICAgICAgJzpzdmc6ZmVEaWZmdXNlTGlnaHRpbmdeOnN2Zzp8JyxcbiAgICAgICAgICAnOnN2ZzpmZURpc3BsYWNlbWVudE1hcF46c3ZnOnwnLFxuICAgICAgICAgICc6c3ZnOmZlRGlzdGFudExpZ2h0Xjpzdmc6fCcsXG4gICAgICAgICAgJzpzdmc6ZmVEcm9wU2hhZG93Xjpzdmc6fCcsXG4gICAgICAgICAgJzpzdmc6ZmVGbG9vZF46c3ZnOnwnLFxuICAgICAgICAgICc6c3ZnOmZlRnVuY0FeOnN2Zzpjb21wb25lbnRUcmFuc2ZlckZ1bmN0aW9ufCcsXG4gICAgICAgICAgJzpzdmc6ZmVGdW5jQl46c3ZnOmNvbXBvbmVudFRyYW5zZmVyRnVuY3Rpb258JyxcbiAgICAgICAgICAnOnN2ZzpmZUZ1bmNHXjpzdmc6Y29tcG9uZW50VHJhbnNmZXJGdW5jdGlvbnwnLFxuICAgICAgICAgICc6c3ZnOmZlRnVuY1JeOnN2Zzpjb21wb25lbnRUcmFuc2ZlckZ1bmN0aW9ufCcsXG4gICAgICAgICAgJzpzdmc6ZmVHYXVzc2lhbkJsdXJeOnN2Zzp8JyxcbiAgICAgICAgICAnOnN2ZzpmZUltYWdlXjpzdmc6fCcsXG4gICAgICAgICAgJzpzdmc6ZmVNZXJnZV46c3ZnOnwnLFxuICAgICAgICAgICc6c3ZnOmZlTWVyZ2VOb2RlXjpzdmc6fCcsXG4gICAgICAgICAgJzpzdmc6ZmVNb3JwaG9sb2d5Xjpzdmc6fCcsXG4gICAgICAgICAgJzpzdmc6ZmVPZmZzZXReOnN2Zzp8JyxcbiAgICAgICAgICAnOnN2ZzpmZVBvaW50TGlnaHReOnN2Zzp8JyxcbiAgICAgICAgICAnOnN2ZzpmZVNwZWN1bGFyTGlnaHRpbmdeOnN2Zzp8JyxcbiAgICAgICAgICAnOnN2ZzpmZVNwb3RMaWdodF46c3ZnOnwnLFxuICAgICAgICAgICc6c3ZnOmZlVGlsZV46c3ZnOnwnLFxuICAgICAgICAgICc6c3ZnOmZlVHVyYnVsZW5jZV46c3ZnOnwnLFxuICAgICAgICAgICc6c3ZnOmZpbHRlcl46c3ZnOnwnLFxuICAgICAgICAgICc6c3ZnOmZvcmVpZ25PYmplY3ReOnN2ZzpncmFwaGljc3wnLFxuICAgICAgICAgICc6c3ZnOmdeOnN2ZzpncmFwaGljc3wnLFxuICAgICAgICAgICc6c3ZnOmltYWdlXjpzdmc6Z3JhcGhpY3N8ZGVjb2RpbmcnLFxuICAgICAgICAgICc6c3ZnOmxpbmVeOnN2ZzpnZW9tZXRyeXwnLFxuICAgICAgICAgICc6c3ZnOmxpbmVhckdyYWRpZW50Xjpzdmc6Z3JhZGllbnR8JyxcbiAgICAgICAgICAnOnN2ZzptcGF0aF46c3ZnOnwnLFxuICAgICAgICAgICc6c3ZnOm1hcmtlcl46c3ZnOnwnLFxuICAgICAgICAgICc6c3ZnOm1hc2teOnN2Zzp8JyxcbiAgICAgICAgICAnOnN2ZzptZXRhZGF0YV46c3ZnOnwnLFxuICAgICAgICAgICc6c3ZnOnBhdGheOnN2ZzpnZW9tZXRyeXwnLFxuICAgICAgICAgICc6c3ZnOnBhdHRlcm5eOnN2Zzp8JyxcbiAgICAgICAgICAnOnN2Zzpwb2x5Z29uXjpzdmc6Z2VvbWV0cnl8JyxcbiAgICAgICAgICAnOnN2Zzpwb2x5bGluZV46c3ZnOmdlb21ldHJ5fCcsXG4gICAgICAgICAgJzpzdmc6cmFkaWFsR3JhZGllbnReOnN2ZzpncmFkaWVudHwnLFxuICAgICAgICAgICc6c3ZnOnJlY3ReOnN2ZzpnZW9tZXRyeXwnLFxuICAgICAgICAgICc6c3ZnOnN2Z146c3ZnOmdyYXBoaWNzfCNjdXJyZW50U2NhbGUsI3pvb21BbmRQYW4nLFxuICAgICAgICAgICc6c3ZnOnNjcmlwdF46c3ZnOnx0eXBlJyxcbiAgICAgICAgICAnOnN2ZzpzZXReOnN2ZzphbmltYXRpb258JyxcbiAgICAgICAgICAnOnN2ZzpzdG9wXjpzdmc6fCcsXG4gICAgICAgICAgJzpzdmc6c3R5bGVeOnN2Zzp8IWRpc2FibGVkLG1lZGlhLHRpdGxlLHR5cGUnLFxuICAgICAgICAgICc6c3ZnOnN3aXRjaF46c3ZnOmdyYXBoaWNzfCcsXG4gICAgICAgICAgJzpzdmc6c3ltYm9sXjpzdmc6fCcsXG4gICAgICAgICAgJzpzdmc6dHNwYW5eOnN2Zzp0ZXh0UG9zaXRpb25pbmd8JyxcbiAgICAgICAgICAnOnN2Zzp0ZXh0Xjpzdmc6dGV4dFBvc2l0aW9uaW5nfCcsXG4gICAgICAgICAgJzpzdmc6dGV4dFBhdGheOnN2Zzp0ZXh0Q29udGVudHwnLFxuICAgICAgICAgICc6c3ZnOnRpdGxlXjpzdmc6fCcsXG4gICAgICAgICAgJzpzdmc6dXNlXjpzdmc6Z3JhcGhpY3N8JyxcbiAgICAgICAgICAnOnN2Zzp2aWV3Xjpzdmc6fCN6b29tQW5kUGFuJyxcbiAgICAgICAgICAnZGF0YV5bSFRNTEVsZW1lbnRdfHZhbHVlJyxcbiAgICAgICAgICAna2V5Z2VuXltIVE1MRWxlbWVudF18IWF1dG9mb2N1cyxjaGFsbGVuZ2UsIWRpc2FibGVkLGZvcm0sa2V5dHlwZSxuYW1lJyxcbiAgICAgICAgICAnbWVudWl0ZW1eW0hUTUxFbGVtZW50XXx0eXBlLGxhYmVsLGljb24sIWRpc2FibGVkLCFjaGVja2VkLHJhZGlvZ3JvdXAsIWRlZmF1bHQnLFxuICAgICAgICAgICdzdW1tYXJ5XltIVE1MRWxlbWVudF18JyxcbiAgICAgICAgICAndGltZV5bSFRNTEVsZW1lbnRdfGRhdGVUaW1lJyxcbiAgICAgICAgICAnOnN2ZzpjdXJzb3JeOnN2Zzp8JyxcbiAgICAgICAgICAnOm1hdGg6XltIVE1MRWxlbWVudF18IWF1dG9mb2N1cyxub25jZSwqYWJvcnQsKmFuaW1hdGlvbmVuZCwqYW5pbWF0aW9uaXRlcmF0aW9uLCphbmltYXRpb25zdGFydCwqYXV4Y2xpY2ssKmJlZm9yZWlucHV0LCpiZWZvcmVtYXRjaCwqYmVmb3JldG9nZ2xlLCpiZWZvcmV4cnNlbGVjdCwqYmx1ciwqY2FuY2VsLCpjYW5wbGF5LCpjYW5wbGF5dGhyb3VnaCwqY2hhbmdlLCpjbGljaywqY2xvc2UsKmNvbnRlbnR2aXNpYmlsaXR5YXV0b3N0YXRlY2hhbmdlLCpjb250ZXh0bG9zdCwqY29udGV4dG1lbnUsKmNvbnRleHRyZXN0b3JlZCwqY29weSwqY3VlY2hhbmdlLCpjdXQsKmRibGNsaWNrLCpkcmFnLCpkcmFnZW5kLCpkcmFnZW50ZXIsKmRyYWdsZWF2ZSwqZHJhZ292ZXIsKmRyYWdzdGFydCwqZHJvcCwqZHVyYXRpb25jaGFuZ2UsKmVtcHRpZWQsKmVuZGVkLCplcnJvciwqZm9jdXMsKmZvcm1kYXRhLCpnb3Rwb2ludGVyY2FwdHVyZSwqaW5wdXQsKmludmFsaWQsKmtleWRvd24sKmtleXByZXNzLCprZXl1cCwqbG9hZCwqbG9hZGVkZGF0YSwqbG9hZGVkbWV0YWRhdGEsKmxvYWRzdGFydCwqbG9zdHBvaW50ZXJjYXB0dXJlLCptb3VzZWRvd24sKm1vdXNlZW50ZXIsKm1vdXNlbGVhdmUsKm1vdXNlbW92ZSwqbW91c2VvdXQsKm1vdXNlb3ZlciwqbW91c2V1cCwqbW91c2V3aGVlbCwqcGFzdGUsKnBhdXNlLCpwbGF5LCpwbGF5aW5nLCpwb2ludGVyY2FuY2VsLCpwb2ludGVyZG93biwqcG9pbnRlcmVudGVyLCpwb2ludGVybGVhdmUsKnBvaW50ZXJtb3ZlLCpwb2ludGVyb3V0LCpwb2ludGVyb3ZlciwqcG9pbnRlcnJhd3VwZGF0ZSwqcG9pbnRlcnVwLCpwcm9ncmVzcywqcmF0ZWNoYW5nZSwqcmVzZXQsKnJlc2l6ZSwqc2Nyb2xsLCpzY3JvbGxlbmQsKnNlY3VyaXR5cG9saWN5dmlvbGF0aW9uLCpzZWVrZWQsKnNlZWtpbmcsKnNlbGVjdCwqc2VsZWN0aW9uY2hhbmdlLCpzZWxlY3RzdGFydCwqc2xvdGNoYW5nZSwqc3RhbGxlZCwqc3VibWl0LCpzdXNwZW5kLCp0aW1ldXBkYXRlLCp0b2dnbGUsKnRyYW5zaXRpb25jYW5jZWwsKnRyYW5zaXRpb25lbmQsKnRyYW5zaXRpb25ydW4sKnRyYW5zaXRpb25zdGFydCwqdm9sdW1lY2hhbmdlLCp3YWl0aW5nLCp3ZWJraXRhbmltYXRpb25lbmQsKndlYmtpdGFuaW1hdGlvbml0ZXJhdGlvbiwqd2Via2l0YW5pbWF0aW9uc3RhcnQsKndlYmtpdHRyYW5zaXRpb25lbmQsKndoZWVsLCVzdHlsZSwjdGFiSW5kZXgnLFxuICAgICAgICAgICc6bWF0aDptYXRoXjptYXRoOnwnLFxuICAgICAgICAgICc6bWF0aDptYWN0aW9uXjptYXRoOnwnLFxuICAgICAgICAgICc6bWF0aDptZW5jbG9zZV46bWF0aDp8JyxcbiAgICAgICAgICAnOm1hdGg6bWVycm9yXjptYXRoOnwnLFxuICAgICAgICAgICc6bWF0aDptZmVuY2VkXjptYXRoOnwnLFxuICAgICAgICAgICc6bWF0aDptZnJhY146bWF0aDp8JyxcbiAgICAgICAgICAnOm1hdGg6bWleOm1hdGg6fCcsXG4gICAgICAgICAgJzptYXRoOm1tdWx0aXNjcmlwdHNeOm1hdGg6fCcsXG4gICAgICAgICAgJzptYXRoOm1uXjptYXRoOnwnLFxuICAgICAgICAgICc6bWF0aDptb146bWF0aDp8JyxcbiAgICAgICAgICAnOm1hdGg6bW92ZXJeOm1hdGg6fCcsXG4gICAgICAgICAgJzptYXRoOm1wYWRkZWReOm1hdGg6fCcsXG4gICAgICAgICAgJzptYXRoOm1waGFudG9tXjptYXRoOnwnLFxuICAgICAgICAgICc6bWF0aDptcm9vdF46bWF0aDp8JyxcbiAgICAgICAgICAnOm1hdGg6bXJvd146bWF0aDp8JyxcbiAgICAgICAgICAnOm1hdGg6bXNeOm1hdGg6fCcsXG4gICAgICAgICAgJzptYXRoOm1zcGFjZV46bWF0aDp8JyxcbiAgICAgICAgICAnOm1hdGg6bXNxcnReOm1hdGg6fCcsXG4gICAgICAgICAgJzptYXRoOm1zdHlsZV46bWF0aDp8JyxcbiAgICAgICAgICAnOm1hdGg6bXN1Yl46bWF0aDp8JyxcbiAgICAgICAgICAnOm1hdGg6bXN1YnN1cF46bWF0aDp8JyxcbiAgICAgICAgICAnOm1hdGg6bXN1cF46bWF0aDp8JyxcbiAgICAgICAgICAnOm1hdGg6bXRhYmxlXjptYXRoOnwnLFxuICAgICAgICAgICc6bWF0aDptdGReOm1hdGg6fCcsXG4gICAgICAgICAgJzptYXRoOm10ZXh0XjptYXRoOnwnLFxuICAgICAgICAgICc6bWF0aDptdHJeOm1hdGg6fCcsXG4gICAgICAgICAgJzptYXRoOm11bmRlcl46bWF0aDp8JyxcbiAgICAgICAgICAnOm1hdGg6bXVuZGVyb3Zlcl46bWF0aDp8JyxcbiAgICAgICAgICAnOm1hdGg6c2VtYW50aWNzXjptYXRoOnwnLFxuICAgICAgICBdO1xuXG5jb25zdCBfQVRUUl9UT19QUk9QID0gbmV3IE1hcChPYmplY3QuZW50cmllcyh7XG4gICdjbGFzcyc6ICdjbGFzc05hbWUnLFxuICAnZm9yJzogJ2h0bWxGb3InLFxuICAnZm9ybWFjdGlvbic6ICdmb3JtQWN0aW9uJyxcbiAgJ2lubmVySHRtbCc6ICdpbm5lckhUTUwnLFxuICAncmVhZG9ubHknOiAncmVhZE9ubHknLFxuICAndGFiaW5kZXgnOiAndGFiSW5kZXgnLFxufSkpO1xuXG4vLyBJbnZlcnQgX0FUVFJfVE9fUFJPUC5cbmNvbnN0IF9QUk9QX1RPX0FUVFIgPVxuICAgIEFycmF5LmZyb20oX0FUVFJfVE9fUFJPUCkucmVkdWNlKChpbnZlcnRlZCwgW3Byb3BlcnR5TmFtZSwgYXR0cmlidXRlTmFtZV0pID0+IHtcbiAgICAgIGludmVydGVkLnNldChwcm9wZXJ0eU5hbWUsIGF0dHJpYnV0ZU5hbWUpO1xuICAgICAgcmV0dXJuIGludmVydGVkO1xuICAgIH0sIG5ldyBNYXA8c3RyaW5nLCBzdHJpbmc+KCkpO1xuXG5leHBvcnQgY2xhc3MgRG9tRWxlbWVudFNjaGVtYVJlZ2lzdHJ5IGV4dGVuZHMgRWxlbWVudFNjaGVtYVJlZ2lzdHJ5IHtcbiAgcHJpdmF0ZSBfc2NoZW1hID0gbmV3IE1hcDxzdHJpbmcsIE1hcDxzdHJpbmcsIHN0cmluZz4+KCk7XG4gIC8vIFdlIGRvbid0IGFsbG93IGJpbmRpbmcgdG8gZXZlbnRzIGZvciBzZWN1cml0eSByZWFzb25zLiBBbGxvd2luZyBldmVudCBiaW5kaW5ncyB3b3VsZCBhbG1vc3RcbiAgLy8gY2VydGFpbmx5IGludHJvZHVjZSBiYWQgWFNTIHZ1bG5lcmFiaWxpdGllcy4gSW5zdGVhZCwgd2Ugc3RvcmUgZXZlbnRzIGluIGEgc2VwYXJhdGUgc2NoZW1hLlxuICBwcml2YXRlIF9ldmVudFNjaGVtYSA9IG5ldyBNYXA8c3RyaW5nLCBTZXQ8c3RyaW5nPj47XG5cbiAgY29uc3RydWN0b3IoKSB7XG4gICAgc3VwZXIoKTtcbiAgICBTQ0hFTUEuZm9yRWFjaChlbmNvZGVkVHlwZSA9PiB7XG4gICAgICBjb25zdCB0eXBlID0gbmV3IE1hcDxzdHJpbmcsIHN0cmluZz4oKTtcbiAgICAgIGNvbnN0IGV2ZW50czogU2V0PHN0cmluZz4gPSBuZXcgU2V0KCk7XG4gICAgICBjb25zdCBbc3RyVHlwZSwgc3RyUHJvcGVydGllc10gPSBlbmNvZGVkVHlwZS5zcGxpdCgnfCcpO1xuICAgICAgY29uc3QgcHJvcGVydGllcyA9IHN0clByb3BlcnRpZXMuc3BsaXQoJywnKTtcbiAgICAgIGNvbnN0IFt0eXBlTmFtZXMsIHN1cGVyTmFtZV0gPSBzdHJUeXBlLnNwbGl0KCdeJyk7XG4gICAgICB0eXBlTmFtZXMuc3BsaXQoJywnKS5mb3JFYWNoKHRhZyA9PiB7XG4gICAgICAgIHRoaXMuX3NjaGVtYS5zZXQodGFnLnRvTG93ZXJDYXNlKCksIHR5cGUpO1xuICAgICAgICB0aGlzLl9ldmVudFNjaGVtYS5zZXQodGFnLnRvTG93ZXJDYXNlKCksIGV2ZW50cyk7XG4gICAgICB9KTtcbiAgICAgIGNvbnN0IHN1cGVyVHlwZSA9IHN1cGVyTmFtZSAmJiB0aGlzLl9zY2hlbWEuZ2V0KHN1cGVyTmFtZS50b0xvd2VyQ2FzZSgpKTtcbiAgICAgIGlmIChzdXBlclR5cGUpIHtcbiAgICAgICAgZm9yIChjb25zdCBbcHJvcCwgdmFsdWVdIG9mIHN1cGVyVHlwZSkge1xuICAgICAgICAgIHR5cGUuc2V0KHByb3AsIHZhbHVlKTtcbiAgICAgICAgfVxuICAgICAgICBmb3IgKGNvbnN0IHN1cGVyRXZlbnQgb2YgdGhpcy5fZXZlbnRTY2hlbWEuZ2V0KHN1cGVyTmFtZS50b0xvd2VyQ2FzZSgpKSEpIHtcbiAgICAgICAgICBldmVudHMuYWRkKHN1cGVyRXZlbnQpO1xuICAgICAgICB9XG4gICAgICB9XG4gICAgICBwcm9wZXJ0aWVzLmZvckVhY2goKHByb3BlcnR5OiBzdHJpbmcpID0+IHtcbiAgICAgICAgaWYgKHByb3BlcnR5Lmxlbmd0aCA+IDApIHtcbiAgICAgICAgICBzd2l0Y2ggKHByb3BlcnR5WzBdKSB7XG4gICAgICAgICAgICBjYXNlICcqJzpcbiAgICAgICAgICAgICAgZXZlbnRzLmFkZChwcm9wZXJ0eS5zdWJzdHJpbmcoMSkpO1xuICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgIGNhc2UgJyEnOlxuICAgICAgICAgICAgICB0eXBlLnNldChwcm9wZXJ0eS5zdWJzdHJpbmcoMSksIEJPT0xFQU4pO1xuICAgICAgICAgICAgICBicmVhaztcbiAgICAgICAgICAgIGNhc2UgJyMnOlxuICAgICAgICAgICAgICB0eXBlLnNldChwcm9wZXJ0eS5zdWJzdHJpbmcoMSksIE5VTUJFUik7XG4gICAgICAgICAgICAgIGJyZWFrO1xuICAgICAgICAgICAgY2FzZSAnJSc6XG4gICAgICAgICAgICAgIHR5cGUuc2V0KHByb3BlcnR5LnN1YnN0cmluZygxKSwgT0JKRUNUKTtcbiAgICAgICAgICAgICAgYnJlYWs7XG4gICAgICAgICAgICBkZWZhdWx0OlxuICAgICAgICAgICAgICB0eXBlLnNldChwcm9wZXJ0eSwgU1RSSU5HKTtcbiAgICAgICAgICB9XG4gICAgICAgIH1cbiAgICAgIH0pO1xuICAgIH0pO1xuICB9XG5cbiAgb3ZlcnJpZGUgaGFzUHJvcGVydHkodGFnTmFtZTogc3RyaW5nLCBwcm9wTmFtZTogc3RyaW5nLCBzY2hlbWFNZXRhczogU2NoZW1hTWV0YWRhdGFbXSk6IGJvb2xlYW4ge1xuICAgIGlmIChzY2hlbWFNZXRhcy5zb21lKChzY2hlbWEpID0+IHNjaGVtYS5uYW1lID09PSBOT19FUlJPUlNfU0NIRU1BLm5hbWUpKSB7XG4gICAgICByZXR1cm4gdHJ1ZTtcbiAgICB9XG5cbiAgICBpZiAodGFnTmFtZS5pbmRleE9mKCctJykgPiAtMSkge1xuICAgICAgaWYgKGlzTmdDb250YWluZXIodGFnTmFtZSkgfHwgaXNOZ0NvbnRlbnQodGFnTmFtZSkpIHtcbiAgICAgICAgcmV0dXJuIGZhbHNlO1xuICAgICAgfVxuXG4gICAgICBpZiAoc2NoZW1hTWV0YXMuc29tZSgoc2NoZW1hKSA9PiBzY2hlbWEubmFtZSA9PT0gQ1VTVE9NX0VMRU1FTlRTX1NDSEVNQS5uYW1lKSkge1xuICAgICAgICAvLyBDYW4ndCB0ZWxsIG5vdyBhcyB3ZSBkb24ndCBrbm93IHdoaWNoIHByb3BlcnRpZXMgYSBjdXN0b20gZWxlbWVudCB3aWxsIGdldFxuICAgICAgICAvLyBvbmNlIGl0IGlzIGluc3RhbnRpYXRlZFxuICAgICAgICByZXR1cm4gdHJ1ZTtcbiAgICAgIH1cbiAgICB9XG5cbiAgICBjb25zdCBlbGVtZW50UHJvcGVydGllcyA9XG4gICAgICAgIHRoaXMuX3NjaGVtYS5nZXQodGFnTmFtZS50b0xvd2VyQ2FzZSgpKSB8fCB0aGlzLl9zY2hlbWEuZ2V0KCd1bmtub3duJykhO1xuICAgIHJldHVybiBlbGVtZW50UHJvcGVydGllcy5oYXMocHJvcE5hbWUpO1xuICB9XG5cbiAgb3ZlcnJpZGUgaGFzRWxlbWVudCh0YWdOYW1lOiBzdHJpbmcsIHNjaGVtYU1ldGFzOiBTY2hlbWFNZXRhZGF0YVtdKTogYm9vbGVhbiB7XG4gICAgaWYgKHNjaGVtYU1ldGFzLnNvbWUoKHNjaGVtYSkgPT4gc2NoZW1hLm5hbWUgPT09IE5PX0VSUk9SU19TQ0hFTUEubmFtZSkpIHtcbiAgICAgIHJldHVybiB0cnVlO1xuICAgIH1cblxuICAgIGlmICh0YWdOYW1lLmluZGV4T2YoJy0nKSA+IC0xKSB7XG4gICAgICBpZiAoaXNOZ0NvbnRhaW5lcih0YWdOYW1lKSB8fCBpc05nQ29udGVudCh0YWdOYW1lKSkge1xuICAgICAgICByZXR1cm4gdHJ1ZTtcbiAgICAgIH1cblxuICAgICAgaWYgKHNjaGVtYU1ldGFzLnNvbWUoKHNjaGVtYSkgPT4gc2NoZW1hLm5hbWUgPT09IENVU1RPTV9FTEVNRU5UU19TQ0hFTUEubmFtZSkpIHtcbiAgICAgICAgLy8gQWxsb3cgYW55IGN1c3RvbSBlbGVtZW50c1xuICAgICAgICByZXR1cm4gdHJ1ZTtcbiAgICAgIH1cbiAgICB9XG5cbiAgICByZXR1cm4gdGhpcy5fc2NoZW1hLmhhcyh0YWdOYW1lLnRvTG93ZXJDYXNlKCkpO1xuICB9XG5cbiAgLyoqXG4gICAqIHNlY3VyaXR5Q29udGV4dCByZXR1cm5zIHRoZSBzZWN1cml0eSBjb250ZXh0IGZvciB0aGUgZ2l2ZW4gcHJvcGVydHkgb24gdGhlIGdpdmVuIERPTSB0YWcuXG4gICAqXG4gICAqIFRhZyBhbmQgcHJvcGVydHkgbmFtZSBhcmUgc3RhdGljYWxseSBrbm93biBhbmQgY2Fubm90IGNoYW5nZSBhdCBydW50aW1lLCBpLmUuIGl0IGlzIG5vdFxuICAgKiBwb3NzaWJsZSB0byBiaW5kIGEgdmFsdWUgaW50byBhIGNoYW5naW5nIGF0dHJpYnV0ZSBvciB0YWcgbmFtZS5cbiAgICpcbiAgICogVGhlIGZpbHRlcmluZyBpcyBiYXNlZCBvbiBhIGxpc3Qgb2YgYWxsb3dlZCB0YWdzfGF0dHJpYnV0ZXMuIEFsbCBhdHRyaWJ1dGVzIGluIHRoZSBzY2hlbWFcbiAgICogYWJvdmUgYXJlIGFzc3VtZWQgdG8gaGF2ZSB0aGUgJ05PTkUnIHNlY3VyaXR5IGNvbnRleHQsIGkuZS4gdGhhdCB0aGV5IGFyZSBzYWZlIGluZXJ0XG4gICAqIHN0cmluZyB2YWx1ZXMuIE9ubHkgc3BlY2lmaWMgd2VsbCBrbm93biBhdHRhY2sgdmVjdG9ycyBhcmUgYXNzaWduZWQgdGhlaXIgYXBwcm9wcmlhdGUgY29udGV4dC5cbiAgICovXG4gIG92ZXJyaWRlIHNlY3VyaXR5Q29udGV4dCh0YWdOYW1lOiBzdHJpbmcsIHByb3BOYW1lOiBzdHJpbmcsIGlzQXR0cmlidXRlOiBib29sZWFuKTpcbiAgICAgIFNlY3VyaXR5Q29udGV4dCB7XG4gICAgaWYgKGlzQXR0cmlidXRlKSB7XG4gICAgICAvLyBOQjogRm9yIHNlY3VyaXR5IHB1cnBvc2VzLCB1c2UgdGhlIG1hcHBlZCBwcm9wZXJ0eSBuYW1lLCBub3QgdGhlIGF0dHJpYnV0ZSBuYW1lLlxuICAgICAgcHJvcE5hbWUgPSB0aGlzLmdldE1hcHBlZFByb3BOYW1lKHByb3BOYW1lKTtcbiAgICB9XG5cbiAgICAvLyBNYWtlIHN1cmUgY29tcGFyaXNvbnMgYXJlIGNhc2UgaW5zZW5zaXRpdmUsIHNvIHRoYXQgY2FzZSBkaWZmZXJlbmNlcyBiZXR3ZWVuIGF0dHJpYnV0ZSBhbmRcbiAgICAvLyBwcm9wZXJ0eSBuYW1lcyBkbyBub3QgaGF2ZSBhIHNlY3VyaXR5IGltcGFjdC5cbiAgICB0YWdOYW1lID0gdGFnTmFtZS50b0xvd2VyQ2FzZSgpO1xuICAgIHByb3BOYW1lID0gcHJvcE5hbWUudG9Mb3dlckNhc2UoKTtcbiAgICBsZXQgY3R4ID0gU0VDVVJJVFlfU0NIRU1BKClbdGFnTmFtZSArICd8JyArIHByb3BOYW1lXTtcbiAgICBpZiAoY3R4KSB7XG4gICAgICByZXR1cm4gY3R4O1xuICAgIH1cbiAgICBjdHggPSBTRUNVUklUWV9TQ0hFTUEoKVsnKnwnICsgcHJvcE5hbWVdO1xuICAgIHJldHVybiBjdHggPyBjdHggOiBTZWN1cml0eUNvbnRleHQuTk9ORTtcbiAgfVxuXG4gIG92ZXJyaWRlIGdldE1hcHBlZFByb3BOYW1lKHByb3BOYW1lOiBzdHJpbmcpOiBzdHJpbmcge1xuICAgIHJldHVybiBfQVRUUl9UT19QUk9QLmdldChwcm9wTmFtZSkgPz8gcHJvcE5hbWU7XG4gIH1cblxuICBvdmVycmlkZSBnZXREZWZhdWx0Q29tcG9uZW50RWxlbWVudE5hbWUoKTogc3RyaW5nIHtcbiAgICByZXR1cm4gJ25nLWNvbXBvbmVudCc7XG4gIH1cblxuICBvdmVycmlkZSB2YWxpZGF0ZVByb3BlcnR5KG5hbWU6IHN0cmluZyk6IHtlcnJvcjogYm9vbGVhbiwgbXNnPzogc3RyaW5nfSB7XG4gICAgaWYgKG5hbWUudG9Mb3dlckNhc2UoKS5zdGFydHNXaXRoKCdvbicpKSB7XG4gICAgICBjb25zdCBtc2cgPSBgQmluZGluZyB0byBldmVudCBwcm9wZXJ0eSAnJHtuYW1lfScgaXMgZGlzYWxsb3dlZCBmb3Igc2VjdXJpdHkgcmVhc29ucywgYCArXG4gICAgICAgICAgYHBsZWFzZSB1c2UgKCR7bmFtZS5zbGljZSgyKX0pPS4uLmAgK1xuICAgICAgICAgIGBcXG5JZiAnJHtuYW1lfScgaXMgYSBkaXJlY3RpdmUgaW5wdXQsIG1ha2Ugc3VyZSB0aGUgZGlyZWN0aXZlIGlzIGltcG9ydGVkIGJ5IHRoZWAgK1xuICAgICAgICAgIGAgY3VycmVudCBtb2R1bGUuYDtcbiAgICAgIHJldHVybiB7ZXJyb3I6IHRydWUsIG1zZzogbXNnfTtcbiAgICB9IGVsc2Uge1xuICAgICAgcmV0dXJuIHtlcnJvcjogZmFsc2V9O1xuICAgIH1cbiAgfVxuXG4gIG92ZXJyaWRlIHZhbGlkYXRlQXR0cmlidXRlKG5hbWU6IHN0cmluZyk6IHtlcnJvcjogYm9vbGVhbiwgbXNnPzogc3RyaW5nfSB7XG4gICAgaWYgKG5hbWUudG9Mb3dlckNhc2UoKS5zdGFydHNXaXRoKCdvbicpKSB7XG4gICAgICBjb25zdCBtc2cgPSBgQmluZGluZyB0byBldmVudCBhdHRyaWJ1dGUgJyR7bmFtZX0nIGlzIGRpc2FsbG93ZWQgZm9yIHNlY3VyaXR5IHJlYXNvbnMsIGAgK1xuICAgICAgICAgIGBwbGVhc2UgdXNlICgke25hbWUuc2xpY2UoMil9KT0uLi5gO1xuICAgICAgcmV0dXJuIHtlcnJvcjogdHJ1ZSwgbXNnOiBtc2d9O1xuICAgIH0gZWxzZSB7XG4gICAgICByZXR1cm4ge2Vycm9yOiBmYWxzZX07XG4gICAgfVxuICB9XG5cbiAgb3ZlcnJpZGUgYWxsS25vd25FbGVtZW50TmFtZXMoKTogc3RyaW5nW10ge1xuICAgIHJldHVybiBBcnJheS5mcm9tKHRoaXMuX3NjaGVtYS5rZXlzKCkpO1xuICB9XG5cbiAgYWxsS25vd25BdHRyaWJ1dGVzT2ZFbGVtZW50KHRhZ05hbWU6IHN0cmluZyk6IHN0cmluZ1tdIHtcbiAgICBjb25zdCBlbGVtZW50UHJvcGVydGllcyA9XG4gICAgICAgIHRoaXMuX3NjaGVtYS5nZXQodGFnTmFtZS50b0xvd2VyQ2FzZSgpKSB8fCB0aGlzLl9zY2hlbWEuZ2V0KCd1bmtub3duJykhO1xuICAgIC8vIENvbnZlcnQgcHJvcGVydGllcyB0byBhdHRyaWJ1dGVzLlxuICAgIHJldHVybiBBcnJheS5mcm9tKGVsZW1lbnRQcm9wZXJ0aWVzLmtleXMoKSkubWFwKHByb3AgPT4gX1BST1BfVE9fQVRUUi5nZXQocHJvcCkgPz8gcHJvcCk7XG4gIH1cblxuICBhbGxLbm93bkV2ZW50c09mRWxlbWVudCh0YWdOYW1lOiBzdHJpbmcpOiBzdHJpbmdbXSB7XG4gICAgcmV0dXJuIEFycmF5LmZyb20odGhpcy5fZXZlbnRTY2hlbWEuZ2V0KHRhZ05hbWUudG9Mb3dlckNhc2UoKSkgPz8gW10pO1xuICB9XG5cbiAgb3ZlcnJpZGUgbm9ybWFsaXplQW5pbWF0aW9uU3R5bGVQcm9wZXJ0eShwcm9wTmFtZTogc3RyaW5nKTogc3RyaW5nIHtcbiAgICByZXR1cm4gZGFzaENhc2VUb0NhbWVsQ2FzZShwcm9wTmFtZSk7XG4gIH1cblxuICBvdmVycmlkZSBub3JtYWxpemVBbmltYXRpb25TdHlsZVZhbHVlKFxuICAgICAgY2FtZWxDYXNlUHJvcDogc3RyaW5nLCB1c2VyUHJvdmlkZWRQcm9wOiBzdHJpbmcsXG4gICAgICB2YWw6IHN0cmluZ3xudW1iZXIpOiB7ZXJyb3I6IHN0cmluZywgdmFsdWU6IHN0cmluZ30ge1xuICAgIGxldCB1bml0OiBzdHJpbmcgPSAnJztcbiAgICBjb25zdCBzdHJWYWwgPSB2YWwudG9TdHJpbmcoKS50cmltKCk7XG4gICAgbGV0IGVycm9yTXNnOiBzdHJpbmcgPSBudWxsITtcblxuICAgIGlmIChfaXNQaXhlbERpbWVuc2lvblN0eWxlKGNhbWVsQ2FzZVByb3ApICYmIHZhbCAhPT0gMCAmJiB2YWwgIT09ICcwJykge1xuICAgICAgaWYgKHR5cGVvZiB2YWwgPT09ICdudW1iZXInKSB7XG4gICAgICAgIHVuaXQgPSAncHgnO1xuICAgICAgfSBlbHNlIHtcbiAgICAgICAgY29uc3QgdmFsQW5kU3VmZml4TWF0Y2ggPSB2YWwubWF0Y2goL15bKy1dP1tcXGRcXC5dKyhbYS16XSopJC8pO1xuICAgICAgICBpZiAodmFsQW5kU3VmZml4TWF0Y2ggJiYgdmFsQW5kU3VmZml4TWF0Y2hbMV0ubGVuZ3RoID09IDApIHtcbiAgICAgICAgICBlcnJvck1zZyA9IGBQbGVhc2UgcHJvdmlkZSBhIENTUyB1bml0IHZhbHVlIGZvciAke3VzZXJQcm92aWRlZFByb3B9OiR7dmFsfWA7XG4gICAgICAgIH1cbiAgICAgIH1cbiAgICB9XG4gICAgcmV0dXJuIHtlcnJvcjogZXJyb3JNc2csIHZhbHVlOiBzdHJWYWwgKyB1bml0fTtcbiAgfVxufVxuXG5mdW5jdGlvbiBfaXNQaXhlbERpbWVuc2lvblN0eWxlKHByb3A6IHN0cmluZyk6IGJvb2xlYW4ge1xuICBzd2l0Y2ggKHByb3ApIHtcbiAgICBjYXNlICd3aWR0aCc6XG4gICAgY2FzZSAnaGVpZ2h0JzpcbiAgICBjYXNlICdtaW5XaWR0aCc6XG4gICAgY2FzZSAnbWluSGVpZ2h0JzpcbiAgICBjYXNlICdtYXhXaWR0aCc6XG4gICAgY2FzZSAnbWF4SGVpZ2h0JzpcbiAgICBjYXNlICdsZWZ0JzpcbiAgICBjYXNlICd0b3AnOlxuICAgIGNhc2UgJ2JvdHRvbSc6XG4gICAgY2FzZSAncmlnaHQnOlxuICAgIGNhc2UgJ2ZvbnRTaXplJzpcbiAgICBjYXNlICdvdXRsaW5lV2lkdGgnOlxuICAgIGNhc2UgJ291dGxpbmVPZmZzZXQnOlxuICAgIGNhc2UgJ3BhZGRpbmdUb3AnOlxuICAgIGNhc2UgJ3BhZGRpbmdMZWZ0JzpcbiAgICBjYXNlICdwYWRkaW5nQm90dG9tJzpcbiAgICBjYXNlICdwYWRkaW5nUmlnaHQnOlxuICAgIGNhc2UgJ21hcmdpblRvcCc6XG4gICAgY2FzZSAnbWFyZ2luTGVmdCc6XG4gICAgY2FzZSAnbWFyZ2luQm90dG9tJzpcbiAgICBjYXNlICdtYXJnaW5SaWdodCc6XG4gICAgY2FzZSAnYm9yZGVyUmFkaXVzJzpcbiAgICBjYXNlICdib3JkZXJXaWR0aCc6XG4gICAgY2FzZSAnYm9yZGVyVG9wV2lkdGgnOlxuICAgIGNhc2UgJ2JvcmRlckxlZnRXaWR0aCc6XG4gICAgY2FzZSAnYm9yZGVyUmlnaHRXaWR0aCc6XG4gICAgY2FzZSAnYm9yZGVyQm90dG9tV2lkdGgnOlxuICAgIGNhc2UgJ3RleHRJbmRlbnQnOlxuICAgICAgcmV0dXJuIHRydWU7XG5cbiAgICBkZWZhdWx0OlxuICAgICAgcmV0dXJuIGZhbHNlO1xuICB9XG59XG4iXX0=