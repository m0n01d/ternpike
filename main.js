(function(scope){
'use strict';

function F(arity, fun, wrapper) {
  wrapper.a = arity;
  wrapper.f = fun;
  return wrapper;
}

function F2(fun) {
  return F(2, fun, function(a) { return function(b) { return fun(a,b); }; })
}
function F3(fun) {
  return F(3, fun, function(a) {
    return function(b) { return function(c) { return fun(a, b, c); }; };
  });
}
function F4(fun) {
  return F(4, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return fun(a, b, c, d); }; }; };
  });
}
function F5(fun) {
  return F(5, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return fun(a, b, c, d, e); }; }; }; };
  });
}
function F6(fun) {
  return F(6, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return fun(a, b, c, d, e, f); }; }; }; }; };
  });
}
function F7(fun) {
  return F(7, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return function(g) { return fun(a, b, c, d, e, f, g); }; }; }; }; }; };
  });
}
function F8(fun) {
  return F(8, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return function(g) { return function(h) {
    return fun(a, b, c, d, e, f, g, h); }; }; }; }; }; }; };
  });
}
function F9(fun) {
  return F(9, fun, function(a) { return function(b) { return function(c) {
    return function(d) { return function(e) { return function(f) {
    return function(g) { return function(h) { return function(i) {
    return fun(a, b, c, d, e, f, g, h, i); }; }; }; }; }; }; }; };
  });
}

function A2(fun, a, b) {
  return fun.a === 2 ? fun.f(a, b) : fun(a)(b);
}
function A3(fun, a, b, c) {
  return fun.a === 3 ? fun.f(a, b, c) : fun(a)(b)(c);
}
function A4(fun, a, b, c, d) {
  return fun.a === 4 ? fun.f(a, b, c, d) : fun(a)(b)(c)(d);
}
function A5(fun, a, b, c, d, e) {
  return fun.a === 5 ? fun.f(a, b, c, d, e) : fun(a)(b)(c)(d)(e);
}
function A6(fun, a, b, c, d, e, f) {
  return fun.a === 6 ? fun.f(a, b, c, d, e, f) : fun(a)(b)(c)(d)(e)(f);
}
function A7(fun, a, b, c, d, e, f, g) {
  return fun.a === 7 ? fun.f(a, b, c, d, e, f, g) : fun(a)(b)(c)(d)(e)(f)(g);
}
function A8(fun, a, b, c, d, e, f, g, h) {
  return fun.a === 8 ? fun.f(a, b, c, d, e, f, g, h) : fun(a)(b)(c)(d)(e)(f)(g)(h);
}
function A9(fun, a, b, c, d, e, f, g, h, i) {
  return fun.a === 9 ? fun.f(a, b, c, d, e, f, g, h, i) : fun(a)(b)(c)(d)(e)(f)(g)(h)(i);
}




var _JsArray_empty = [];

function _JsArray_singleton(value)
{
    return [value];
}

function _JsArray_length(array)
{
    return array.length;
}

var _JsArray_initialize = F3(function(size, offset, func)
{
    var result = new Array(size);

    for (var i = 0; i < size; i++)
    {
        result[i] = func(offset + i);
    }

    return result;
});

var _JsArray_initializeFromList = F2(function (max, ls)
{
    var result = new Array(max);

    for (var i = 0; i < max && ls.b; i++)
    {
        result[i] = ls.a;
        ls = ls.b;
    }

    result.length = i;
    return _Utils_Tuple2(result, ls);
});

var _JsArray_unsafeGet = F2(function(index, array)
{
    return array[index];
});

var _JsArray_unsafeSet = F3(function(index, value, array)
{
    var length = array.length;
    var result = new Array(length);

    for (var i = 0; i < length; i++)
    {
        result[i] = array[i];
    }

    result[index] = value;
    return result;
});

var _JsArray_push = F2(function(value, array)
{
    var length = array.length;
    var result = new Array(length + 1);

    for (var i = 0; i < length; i++)
    {
        result[i] = array[i];
    }

    result[length] = value;
    return result;
});

var _JsArray_foldl = F3(function(func, acc, array)
{
    var length = array.length;

    for (var i = 0; i < length; i++)
    {
        acc = A2(func, array[i], acc);
    }

    return acc;
});

var _JsArray_foldr = F3(function(func, acc, array)
{
    for (var i = array.length - 1; i >= 0; i--)
    {
        acc = A2(func, array[i], acc);
    }

    return acc;
});

var _JsArray_map = F2(function(func, array)
{
    var length = array.length;
    var result = new Array(length);

    for (var i = 0; i < length; i++)
    {
        result[i] = func(array[i]);
    }

    return result;
});

var _JsArray_indexedMap = F3(function(func, offset, array)
{
    var length = array.length;
    var result = new Array(length);

    for (var i = 0; i < length; i++)
    {
        result[i] = A2(func, offset + i, array[i]);
    }

    return result;
});

var _JsArray_slice = F3(function(from, to, array)
{
    return array.slice(from, to);
});

var _JsArray_appendN = F3(function(n, dest, source)
{
    var destLen = dest.length;
    var itemsToCopy = n - destLen;

    if (itemsToCopy > source.length)
    {
        itemsToCopy = source.length;
    }

    var size = destLen + itemsToCopy;
    var result = new Array(size);

    for (var i = 0; i < destLen; i++)
    {
        result[i] = dest[i];
    }

    for (var i = 0; i < itemsToCopy; i++)
    {
        result[i + destLen] = source[i];
    }

    return result;
});



// LOG

var _Debug_log = F2(function(tag, value)
{
	return value;
});

var _Debug_log_UNUSED = F2(function(tag, value)
{
	console.log(tag + ': ' + _Debug_toString(value));
	return value;
});


// TODOS

function _Debug_todo(moduleName, region)
{
	return function(message) {
		_Debug_crash(8, moduleName, region, message);
	};
}

function _Debug_todoCase(moduleName, region, value)
{
	return function(message) {
		_Debug_crash(9, moduleName, region, value, message);
	};
}


// TO STRING

function _Debug_toString(value)
{
	return '<internals>';
}

function _Debug_toString_UNUSED(value)
{
	return _Debug_toAnsiString(false, value);
}

function _Debug_toAnsiString(ansi, value)
{
	if (typeof value === 'function')
	{
		return _Debug_internalColor(ansi, '<function>');
	}

	if (typeof value === 'boolean')
	{
		return _Debug_ctorColor(ansi, value ? 'True' : 'False');
	}

	if (typeof value === 'number')
	{
		return _Debug_numberColor(ansi, value + '');
	}

	if (value instanceof String)
	{
		return _Debug_charColor(ansi, "'" + _Debug_addSlashes(value, true) + "'");
	}

	if (typeof value === 'string')
	{
		return _Debug_stringColor(ansi, '"' + _Debug_addSlashes(value, false) + '"');
	}

	if (typeof value === 'object' && '$' in value)
	{
		var tag = value.$;

		if (typeof tag === 'number')
		{
			return _Debug_internalColor(ansi, '<internals>');
		}

		if (tag[0] === '#')
		{
			var output = [];
			for (var k in value)
			{
				if (k === '$') continue;
				output.push(_Debug_toAnsiString(ansi, value[k]));
			}
			return '(' + output.join(',') + ')';
		}

		if (tag === 'Set_elm_builtin')
		{
			return _Debug_ctorColor(ansi, 'Set')
				+ _Debug_fadeColor(ansi, '.fromList') + ' '
				+ _Debug_toAnsiString(ansi, $elm$core$Set$toList(value));
		}

		if (tag === 'RBNode_elm_builtin' || tag === 'RBEmpty_elm_builtin')
		{
			return _Debug_ctorColor(ansi, 'Dict')
				+ _Debug_fadeColor(ansi, '.fromList') + ' '
				+ _Debug_toAnsiString(ansi, $elm$core$Dict$toList(value));
		}

		if (tag === 'Array_elm_builtin')
		{
			return _Debug_ctorColor(ansi, 'Array')
				+ _Debug_fadeColor(ansi, '.fromList') + ' '
				+ _Debug_toAnsiString(ansi, $elm$core$Array$toList(value));
		}

		if (tag === '::' || tag === '[]')
		{
			var output = '[';

			value.b && (output += _Debug_toAnsiString(ansi, value.a), value = value.b)

			for (; value.b; value = value.b) // WHILE_CONS
			{
				output += ',' + _Debug_toAnsiString(ansi, value.a);
			}
			return output + ']';
		}

		var output = '';
		for (var i in value)
		{
			if (i === '$') continue;
			var str = _Debug_toAnsiString(ansi, value[i]);
			var c0 = str[0];
			var parenless = c0 === '{' || c0 === '(' || c0 === '[' || c0 === '<' || c0 === '"' || str.indexOf(' ') < 0;
			output += ' ' + (parenless ? str : '(' + str + ')');
		}
		return _Debug_ctorColor(ansi, tag) + output;
	}

	if (typeof DataView === 'function' && value instanceof DataView)
	{
		return _Debug_stringColor(ansi, '<' + value.byteLength + ' bytes>');
	}

	if (typeof File !== 'undefined' && value instanceof File)
	{
		return _Debug_internalColor(ansi, '<' + value.name + '>');
	}

	if (typeof value === 'object')
	{
		var output = [];
		for (var key in value)
		{
			var field = key[0] === '_' ? key.slice(1) : key;
			output.push(_Debug_fadeColor(ansi, field) + ' = ' + _Debug_toAnsiString(ansi, value[key]));
		}
		if (output.length === 0)
		{
			return '{}';
		}
		return '{ ' + output.join(', ') + ' }';
	}

	return _Debug_internalColor(ansi, '<internals>');
}

function _Debug_addSlashes(str, isChar)
{
	var s = str
		.replace(/\\/g, '\\\\')
		.replace(/\n/g, '\\n')
		.replace(/\t/g, '\\t')
		.replace(/\r/g, '\\r')
		.replace(/\v/g, '\\v')
		.replace(/\0/g, '\\0');

	if (isChar)
	{
		return s.replace(/\'/g, '\\\'');
	}
	else
	{
		return s.replace(/\"/g, '\\"');
	}
}

function _Debug_ctorColor(ansi, string)
{
	return ansi ? '\x1b[96m' + string + '\x1b[0m' : string;
}

function _Debug_numberColor(ansi, string)
{
	return ansi ? '\x1b[95m' + string + '\x1b[0m' : string;
}

function _Debug_stringColor(ansi, string)
{
	return ansi ? '\x1b[93m' + string + '\x1b[0m' : string;
}

function _Debug_charColor(ansi, string)
{
	return ansi ? '\x1b[92m' + string + '\x1b[0m' : string;
}

function _Debug_fadeColor(ansi, string)
{
	return ansi ? '\x1b[37m' + string + '\x1b[0m' : string;
}

function _Debug_internalColor(ansi, string)
{
	return ansi ? '\x1b[36m' + string + '\x1b[0m' : string;
}

function _Debug_toHexDigit(n)
{
	return String.fromCharCode(n < 10 ? 48 + n : 55 + n);
}


// CRASH


function _Debug_crash(identifier)
{
	throw new Error('https://github.com/elm/core/blob/1.0.0/hints/' + identifier + '.md');
}


function _Debug_crash_UNUSED(identifier, fact1, fact2, fact3, fact4)
{
	switch(identifier)
	{
		case 0:
			throw new Error('What node should I take over? In JavaScript I need something like:\n\n    Elm.Main.init({\n        node: document.getElementById("elm-node")\n    })\n\nYou need to do this with any Browser.sandbox or Browser.element program.');

		case 1:
			throw new Error('Browser.application programs cannot handle URLs like this:\n\n    ' + document.location.href + '\n\nWhat is the root? The root of your file system? Try looking at this program with `elm reactor` or some other server.');

		case 2:
			var jsonErrorString = fact1;
			throw new Error('Problem with the flags given to your Elm program on initialization.\n\n' + jsonErrorString);

		case 3:
			var portName = fact1;
			throw new Error('There can only be one port named `' + portName + '`, but your program has multiple.');

		case 4:
			var portName = fact1;
			var problem = fact2;
			throw new Error('Trying to send an unexpected type of value through port `' + portName + '`:\n' + problem);

		case 5:
			throw new Error('Trying to use `(==)` on functions.\nThere is no way to know if functions are "the same" in the Elm sense.\nRead more about this at https://package.elm-lang.org/packages/elm/core/latest/Basics#== which describes why it is this way and what the better version will look like.');

		case 6:
			var moduleName = fact1;
			throw new Error('Your page is loading multiple Elm scripts with a module named ' + moduleName + '. Maybe a duplicate script is getting loaded accidentally? If not, rename one of them so I know which is which!');

		case 8:
			var moduleName = fact1;
			var region = fact2;
			var message = fact3;
			throw new Error('TODO in module `' + moduleName + '` ' + _Debug_regionToString(region) + '\n\n' + message);

		case 9:
			var moduleName = fact1;
			var region = fact2;
			var value = fact3;
			var message = fact4;
			throw new Error(
				'TODO in module `' + moduleName + '` from the `case` expression '
				+ _Debug_regionToString(region) + '\n\nIt received the following value:\n\n    '
				+ _Debug_toString(value).replace('\n', '\n    ')
				+ '\n\nBut the branch that handles it says:\n\n    ' + message.replace('\n', '\n    ')
			);

		case 10:
			throw new Error('Bug in https://github.com/elm/virtual-dom/issues');

		case 11:
			throw new Error('Cannot perform mod 0. Division by zero error.');
	}
}

function _Debug_regionToString(region)
{
	if (region.b1.a6 === region.cj.a6)
	{
		return 'on line ' + region.b1.a6;
	}
	return 'on lines ' + region.b1.a6 + ' through ' + region.cj.a6;
}



// EQUALITY

function _Utils_eq(x, y)
{
	for (
		var pair, stack = [], isEqual = _Utils_eqHelp(x, y, 0, stack);
		isEqual && (pair = stack.pop());
		isEqual = _Utils_eqHelp(pair.a, pair.b, 0, stack)
		)
	{}

	return isEqual;
}

function _Utils_eqHelp(x, y, depth, stack)
{
	if (x === y)
	{
		return true;
	}

	if (typeof x !== 'object' || x === null || y === null)
	{
		typeof x === 'function' && _Debug_crash(5);
		return false;
	}

	if (depth > 100)
	{
		stack.push(_Utils_Tuple2(x,y));
		return true;
	}

	/**_UNUSED/
	if (x.$ === 'Set_elm_builtin')
	{
		x = $elm$core$Set$toList(x);
		y = $elm$core$Set$toList(y);
	}
	if (x.$ === 'RBNode_elm_builtin' || x.$ === 'RBEmpty_elm_builtin')
	{
		x = $elm$core$Dict$toList(x);
		y = $elm$core$Dict$toList(y);
	}
	//*/

	/**/
	if (x.$ < 0)
	{
		x = $elm$core$Dict$toList(x);
		y = $elm$core$Dict$toList(y);
	}
	//*/

	for (var key in x)
	{
		if (!_Utils_eqHelp(x[key], y[key], depth + 1, stack))
		{
			return false;
		}
	}
	return true;
}

var _Utils_equal = F2(_Utils_eq);
var _Utils_notEqual = F2(function(a, b) { return !_Utils_eq(a,b); });



// COMPARISONS

// Code in Generate/JavaScript.hs, Basics.js, and List.js depends on
// the particular integer values assigned to LT, EQ, and GT.

function _Utils_cmp(x, y, ord)
{
	if (typeof x !== 'object')
	{
		return x === y ? /*EQ*/ 0 : x < y ? /*LT*/ -1 : /*GT*/ 1;
	}

	/**_UNUSED/
	if (x instanceof String)
	{
		var a = x.valueOf();
		var b = y.valueOf();
		return a === b ? 0 : a < b ? -1 : 1;
	}
	//*/

	/**/
	if (typeof x.$ === 'undefined')
	//*/
	/**_UNUSED/
	if (x.$[0] === '#')
	//*/
	{
		return (ord = _Utils_cmp(x.a, y.a))
			? ord
			: (ord = _Utils_cmp(x.b, y.b))
				? ord
				: _Utils_cmp(x.c, y.c);
	}

	// traverse conses until end of a list or a mismatch
	for (; x.b && y.b && !(ord = _Utils_cmp(x.a, y.a)); x = x.b, y = y.b) {} // WHILE_CONSES
	return ord || (x.b ? /*GT*/ 1 : y.b ? /*LT*/ -1 : /*EQ*/ 0);
}

var _Utils_lt = F2(function(a, b) { return _Utils_cmp(a, b) < 0; });
var _Utils_le = F2(function(a, b) { return _Utils_cmp(a, b) < 1; });
var _Utils_gt = F2(function(a, b) { return _Utils_cmp(a, b) > 0; });
var _Utils_ge = F2(function(a, b) { return _Utils_cmp(a, b) >= 0; });

var _Utils_compare = F2(function(x, y)
{
	var n = _Utils_cmp(x, y);
	return n < 0 ? $elm$core$Basics$LT : n ? $elm$core$Basics$GT : $elm$core$Basics$EQ;
});


// COMMON VALUES

var _Utils_Tuple0 = 0;
var _Utils_Tuple0_UNUSED = { $: '#0' };

function _Utils_Tuple2(a, b) { return { a: a, b: b }; }
function _Utils_Tuple2_UNUSED(a, b) { return { $: '#2', a: a, b: b }; }

function _Utils_Tuple3(a, b, c) { return { a: a, b: b, c: c }; }
function _Utils_Tuple3_UNUSED(a, b, c) { return { $: '#3', a: a, b: b, c: c }; }

function _Utils_chr(c) { return c; }
function _Utils_chr_UNUSED(c) { return new String(c); }


// RECORDS

function _Utils_update(oldRecord, updatedFields)
{
	var newRecord = {};

	for (var key in oldRecord)
	{
		newRecord[key] = oldRecord[key];
	}

	for (var key in updatedFields)
	{
		newRecord[key] = updatedFields[key];
	}

	return newRecord;
}


// APPEND

var _Utils_append = F2(_Utils_ap);

function _Utils_ap(xs, ys)
{
	// append Strings
	if (typeof xs === 'string')
	{
		return xs + ys;
	}

	// append Lists
	if (!xs.b)
	{
		return ys;
	}
	var root = _List_Cons(xs.a, ys);
	xs = xs.b
	for (var curr = root; xs.b; xs = xs.b) // WHILE_CONS
	{
		curr = curr.b = _List_Cons(xs.a, ys);
	}
	return root;
}



var _List_Nil = { $: 0 };
var _List_Nil_UNUSED = { $: '[]' };

function _List_Cons(hd, tl) { return { $: 1, a: hd, b: tl }; }
function _List_Cons_UNUSED(hd, tl) { return { $: '::', a: hd, b: tl }; }


var _List_cons = F2(_List_Cons);

function _List_fromArray(arr)
{
	var out = _List_Nil;
	for (var i = arr.length; i--; )
	{
		out = _List_Cons(arr[i], out);
	}
	return out;
}

function _List_toArray(xs)
{
	for (var out = []; xs.b; xs = xs.b) // WHILE_CONS
	{
		out.push(xs.a);
	}
	return out;
}

var _List_map2 = F3(function(f, xs, ys)
{
	for (var arr = []; xs.b && ys.b; xs = xs.b, ys = ys.b) // WHILE_CONSES
	{
		arr.push(A2(f, xs.a, ys.a));
	}
	return _List_fromArray(arr);
});

var _List_map3 = F4(function(f, xs, ys, zs)
{
	for (var arr = []; xs.b && ys.b && zs.b; xs = xs.b, ys = ys.b, zs = zs.b) // WHILE_CONSES
	{
		arr.push(A3(f, xs.a, ys.a, zs.a));
	}
	return _List_fromArray(arr);
});

var _List_map4 = F5(function(f, ws, xs, ys, zs)
{
	for (var arr = []; ws.b && xs.b && ys.b && zs.b; ws = ws.b, xs = xs.b, ys = ys.b, zs = zs.b) // WHILE_CONSES
	{
		arr.push(A4(f, ws.a, xs.a, ys.a, zs.a));
	}
	return _List_fromArray(arr);
});

var _List_map5 = F6(function(f, vs, ws, xs, ys, zs)
{
	for (var arr = []; vs.b && ws.b && xs.b && ys.b && zs.b; vs = vs.b, ws = ws.b, xs = xs.b, ys = ys.b, zs = zs.b) // WHILE_CONSES
	{
		arr.push(A5(f, vs.a, ws.a, xs.a, ys.a, zs.a));
	}
	return _List_fromArray(arr);
});

var _List_sortBy = F2(function(f, xs)
{
	return _List_fromArray(_List_toArray(xs).sort(function(a, b) {
		return _Utils_cmp(f(a), f(b));
	}));
});

var _List_sortWith = F2(function(f, xs)
{
	return _List_fromArray(_List_toArray(xs).sort(function(a, b) {
		var ord = A2(f, a, b);
		return ord === $elm$core$Basics$EQ ? 0 : ord === $elm$core$Basics$LT ? -1 : 1;
	}));
});



// MATH

var _Basics_add = F2(function(a, b) { return a + b; });
var _Basics_sub = F2(function(a, b) { return a - b; });
var _Basics_mul = F2(function(a, b) { return a * b; });
var _Basics_fdiv = F2(function(a, b) { return a / b; });
var _Basics_idiv = F2(function(a, b) { return (a / b) | 0; });
var _Basics_pow = F2(Math.pow);

var _Basics_remainderBy = F2(function(b, a) { return a % b; });

// https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/divmodnote-letter.pdf
var _Basics_modBy = F2(function(modulus, x)
{
	var answer = x % modulus;
	return modulus === 0
		? _Debug_crash(11)
		:
	((answer > 0 && modulus < 0) || (answer < 0 && modulus > 0))
		? answer + modulus
		: answer;
});


// TRIGONOMETRY

var _Basics_pi = Math.PI;
var _Basics_e = Math.E;
var _Basics_cos = Math.cos;
var _Basics_sin = Math.sin;
var _Basics_tan = Math.tan;
var _Basics_acos = Math.acos;
var _Basics_asin = Math.asin;
var _Basics_atan = Math.atan;
var _Basics_atan2 = F2(Math.atan2);


// MORE MATH

function _Basics_toFloat(x) { return x; }
function _Basics_truncate(n) { return n | 0; }
function _Basics_isInfinite(n) { return n === Infinity || n === -Infinity; }

var _Basics_ceiling = Math.ceil;
var _Basics_floor = Math.floor;
var _Basics_round = Math.round;
var _Basics_sqrt = Math.sqrt;
var _Basics_log = Math.log;
var _Basics_isNaN = isNaN;


// BOOLEANS

function _Basics_not(bool) { return !bool; }
var _Basics_and = F2(function(a, b) { return a && b; });
var _Basics_or  = F2(function(a, b) { return a || b; });
var _Basics_xor = F2(function(a, b) { return a !== b; });



var _String_cons = F2(function(chr, str)
{
	return chr + str;
});

function _String_uncons(string)
{
	var word = string.charCodeAt(0);
	return !isNaN(word)
		? $elm$core$Maybe$Just(
			0xD800 <= word && word <= 0xDBFF
				? _Utils_Tuple2(_Utils_chr(string[0] + string[1]), string.slice(2))
				: _Utils_Tuple2(_Utils_chr(string[0]), string.slice(1))
		)
		: $elm$core$Maybe$Nothing;
}

var _String_append = F2(function(a, b)
{
	return a + b;
});

function _String_length(str)
{
	return str.length;
}

var _String_map = F2(function(func, string)
{
	var len = string.length;
	var array = new Array(len);
	var i = 0;
	while (i < len)
	{
		var word = string.charCodeAt(i);
		if (0xD800 <= word && word <= 0xDBFF)
		{
			array[i] = func(_Utils_chr(string[i] + string[i+1]));
			i += 2;
			continue;
		}
		array[i] = func(_Utils_chr(string[i]));
		i++;
	}
	return array.join('');
});

var _String_filter = F2(function(isGood, str)
{
	var arr = [];
	var len = str.length;
	var i = 0;
	while (i < len)
	{
		var char = str[i];
		var word = str.charCodeAt(i);
		i++;
		if (0xD800 <= word && word <= 0xDBFF)
		{
			char += str[i];
			i++;
		}

		if (isGood(_Utils_chr(char)))
		{
			arr.push(char);
		}
	}
	return arr.join('');
});

function _String_reverse(str)
{
	var len = str.length;
	var arr = new Array(len);
	var i = 0;
	while (i < len)
	{
		var word = str.charCodeAt(i);
		if (0xD800 <= word && word <= 0xDBFF)
		{
			arr[len - i] = str[i + 1];
			i++;
			arr[len - i] = str[i - 1];
			i++;
		}
		else
		{
			arr[len - i] = str[i];
			i++;
		}
	}
	return arr.join('');
}

var _String_foldl = F3(function(func, state, string)
{
	var len = string.length;
	var i = 0;
	while (i < len)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		i++;
		if (0xD800 <= word && word <= 0xDBFF)
		{
			char += string[i];
			i++;
		}
		state = A2(func, _Utils_chr(char), state);
	}
	return state;
});

var _String_foldr = F3(function(func, state, string)
{
	var i = string.length;
	while (i--)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		if (0xDC00 <= word && word <= 0xDFFF)
		{
			i--;
			char = string[i] + char;
		}
		state = A2(func, _Utils_chr(char), state);
	}
	return state;
});

var _String_split = F2(function(sep, str)
{
	return str.split(sep);
});

var _String_join = F2(function(sep, strs)
{
	return strs.join(sep);
});

var _String_slice = F3(function(start, end, str) {
	return str.slice(start, end);
});

function _String_trim(str)
{
	return str.trim();
}

function _String_trimLeft(str)
{
	return str.replace(/^\s+/, '');
}

function _String_trimRight(str)
{
	return str.replace(/\s+$/, '');
}

function _String_words(str)
{
	return _List_fromArray(str.trim().split(/\s+/g));
}

function _String_lines(str)
{
	return _List_fromArray(str.split(/\r\n|\r|\n/g));
}

function _String_toUpper(str)
{
	return str.toUpperCase();
}

function _String_toLower(str)
{
	return str.toLowerCase();
}

var _String_any = F2(function(isGood, string)
{
	var i = string.length;
	while (i--)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		if (0xDC00 <= word && word <= 0xDFFF)
		{
			i--;
			char = string[i] + char;
		}
		if (isGood(_Utils_chr(char)))
		{
			return true;
		}
	}
	return false;
});

var _String_all = F2(function(isGood, string)
{
	var i = string.length;
	while (i--)
	{
		var char = string[i];
		var word = string.charCodeAt(i);
		if (0xDC00 <= word && word <= 0xDFFF)
		{
			i--;
			char = string[i] + char;
		}
		if (!isGood(_Utils_chr(char)))
		{
			return false;
		}
	}
	return true;
});

var _String_contains = F2(function(sub, str)
{
	return str.indexOf(sub) > -1;
});

var _String_startsWith = F2(function(sub, str)
{
	return str.indexOf(sub) === 0;
});

var _String_endsWith = F2(function(sub, str)
{
	return str.length >= sub.length &&
		str.lastIndexOf(sub) === str.length - sub.length;
});

var _String_indexes = F2(function(sub, str)
{
	var subLen = sub.length;

	if (subLen < 1)
	{
		return _List_Nil;
	}

	var i = 0;
	var is = [];

	while ((i = str.indexOf(sub, i)) > -1)
	{
		is.push(i);
		i = i + subLen;
	}

	return _List_fromArray(is);
});


// TO STRING

function _String_fromNumber(number)
{
	return number + '';
}


// INT CONVERSIONS

function _String_toInt(str)
{
	var total = 0;
	var code0 = str.charCodeAt(0);
	var start = code0 == 0x2B /* + */ || code0 == 0x2D /* - */ ? 1 : 0;

	for (var i = start; i < str.length; ++i)
	{
		var code = str.charCodeAt(i);
		if (code < 0x30 || 0x39 < code)
		{
			return $elm$core$Maybe$Nothing;
		}
		total = 10 * total + code - 0x30;
	}

	return i == start
		? $elm$core$Maybe$Nothing
		: $elm$core$Maybe$Just(code0 == 0x2D ? -total : total);
}


// FLOAT CONVERSIONS

function _String_toFloat(s)
{
	// check if it is a hex, octal, or binary number
	if (s.length === 0 || /[\sxbo]/.test(s))
	{
		return $elm$core$Maybe$Nothing;
	}
	var n = +s;
	// faster isNaN check
	return n === n ? $elm$core$Maybe$Just(n) : $elm$core$Maybe$Nothing;
}

function _String_fromList(chars)
{
	return _List_toArray(chars).join('');
}




function _Char_toCode(char)
{
	var code = char.charCodeAt(0);
	if (0xD800 <= code && code <= 0xDBFF)
	{
		return (code - 0xD800) * 0x400 + char.charCodeAt(1) - 0xDC00 + 0x10000
	}
	return code;
}

function _Char_fromCode(code)
{
	return _Utils_chr(
		(code < 0 || 0x10FFFF < code)
			? '\uFFFD'
			:
		(code <= 0xFFFF)
			? String.fromCharCode(code)
			:
		(code -= 0x10000,
			String.fromCharCode(Math.floor(code / 0x400) + 0xD800, code % 0x400 + 0xDC00)
		)
	);
}

function _Char_toUpper(char)
{
	return _Utils_chr(char.toUpperCase());
}

function _Char_toLower(char)
{
	return _Utils_chr(char.toLowerCase());
}

function _Char_toLocaleUpper(char)
{
	return _Utils_chr(char.toLocaleUpperCase());
}

function _Char_toLocaleLower(char)
{
	return _Utils_chr(char.toLocaleLowerCase());
}



/**_UNUSED/
function _Json_errorToString(error)
{
	return $elm$json$Json$Decode$errorToString(error);
}
//*/


// CORE DECODERS

function _Json_succeed(msg)
{
	return {
		$: 0,
		a: msg
	};
}

function _Json_fail(msg)
{
	return {
		$: 1,
		a: msg
	};
}

function _Json_decodePrim(decoder)
{
	return { $: 2, b: decoder };
}

var _Json_decodeInt = _Json_decodePrim(function(value) {
	return (typeof value !== 'number')
		? _Json_expecting('an INT', value)
		:
	(-2147483647 < value && value < 2147483647 && (value | 0) === value)
		? $elm$core$Result$Ok(value)
		:
	(isFinite(value) && !(value % 1))
		? $elm$core$Result$Ok(value)
		: _Json_expecting('an INT', value);
});

var _Json_decodeBool = _Json_decodePrim(function(value) {
	return (typeof value === 'boolean')
		? $elm$core$Result$Ok(value)
		: _Json_expecting('a BOOL', value);
});

var _Json_decodeFloat = _Json_decodePrim(function(value) {
	return (typeof value === 'number')
		? $elm$core$Result$Ok(value)
		: _Json_expecting('a FLOAT', value);
});

var _Json_decodeValue = _Json_decodePrim(function(value) {
	return $elm$core$Result$Ok(_Json_wrap(value));
});

var _Json_decodeString = _Json_decodePrim(function(value) {
	return (typeof value === 'string')
		? $elm$core$Result$Ok(value)
		: (value instanceof String)
			? $elm$core$Result$Ok(value + '')
			: _Json_expecting('a STRING', value);
});

function _Json_decodeList(decoder) { return { $: 3, b: decoder }; }
function _Json_decodeArray(decoder) { return { $: 4, b: decoder }; }

function _Json_decodeNull(value) { return { $: 5, c: value }; }

var _Json_decodeField = F2(function(field, decoder)
{
	return {
		$: 6,
		d: field,
		b: decoder
	};
});

var _Json_decodeIndex = F2(function(index, decoder)
{
	return {
		$: 7,
		e: index,
		b: decoder
	};
});

function _Json_decodeKeyValuePairs(decoder)
{
	return {
		$: 8,
		b: decoder
	};
}

function _Json_mapMany(f, decoders)
{
	return {
		$: 9,
		f: f,
		g: decoders
	};
}

var _Json_andThen = F2(function(callback, decoder)
{
	return {
		$: 10,
		b: decoder,
		h: callback
	};
});

function _Json_oneOf(decoders)
{
	return {
		$: 11,
		g: decoders
	};
}


// DECODING OBJECTS

var _Json_map1 = F2(function(f, d1)
{
	return _Json_mapMany(f, [d1]);
});

var _Json_map2 = F3(function(f, d1, d2)
{
	return _Json_mapMany(f, [d1, d2]);
});

var _Json_map3 = F4(function(f, d1, d2, d3)
{
	return _Json_mapMany(f, [d1, d2, d3]);
});

var _Json_map4 = F5(function(f, d1, d2, d3, d4)
{
	return _Json_mapMany(f, [d1, d2, d3, d4]);
});

var _Json_map5 = F6(function(f, d1, d2, d3, d4, d5)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5]);
});

var _Json_map6 = F7(function(f, d1, d2, d3, d4, d5, d6)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5, d6]);
});

var _Json_map7 = F8(function(f, d1, d2, d3, d4, d5, d6, d7)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5, d6, d7]);
});

var _Json_map8 = F9(function(f, d1, d2, d3, d4, d5, d6, d7, d8)
{
	return _Json_mapMany(f, [d1, d2, d3, d4, d5, d6, d7, d8]);
});


// DECODE

var _Json_runOnString = F2(function(decoder, string)
{
	try
	{
		var value = JSON.parse(string);
		return _Json_runHelp(decoder, value);
	}
	catch (e)
	{
		return $elm$core$Result$Err(A2($elm$json$Json$Decode$Failure, 'This is not valid JSON! ' + e.message, _Json_wrap(string)));
	}
});

var _Json_run = F2(function(decoder, value)
{
	return _Json_runHelp(decoder, _Json_unwrap(value));
});

function _Json_runHelp(decoder, value)
{
	switch (decoder.$)
	{
		case 2:
			return decoder.b(value);

		case 5:
			return (value === null)
				? $elm$core$Result$Ok(decoder.c)
				: _Json_expecting('null', value);

		case 3:
			if (!_Json_isArray(value))
			{
				return _Json_expecting('a LIST', value);
			}
			return _Json_runArrayDecoder(decoder.b, value, _List_fromArray);

		case 4:
			if (!_Json_isArray(value))
			{
				return _Json_expecting('an ARRAY', value);
			}
			return _Json_runArrayDecoder(decoder.b, value, _Json_toElmArray);

		case 6:
			var field = decoder.d;
			if (typeof value !== 'object' || value === null || !(field in value))
			{
				return _Json_expecting('an OBJECT with a field named `' + field + '`', value);
			}
			var result = _Json_runHelp(decoder.b, value[field]);
			return ($elm$core$Result$isOk(result)) ? result : $elm$core$Result$Err(A2($elm$json$Json$Decode$Field, field, result.a));

		case 7:
			var index = decoder.e;
			if (!_Json_isArray(value))
			{
				return _Json_expecting('an ARRAY', value);
			}
			if (index >= value.length)
			{
				return _Json_expecting('a LONGER array. Need index ' + index + ' but only see ' + value.length + ' entries', value);
			}
			var result = _Json_runHelp(decoder.b, value[index]);
			return ($elm$core$Result$isOk(result)) ? result : $elm$core$Result$Err(A2($elm$json$Json$Decode$Index, index, result.a));

		case 8:
			if (typeof value !== 'object' || value === null || _Json_isArray(value))
			{
				return _Json_expecting('an OBJECT', value);
			}

			var keyValuePairs = _List_Nil;
			// TODO test perf of Object.keys and switch when support is good enough
			for (var key in value)
			{
				if (Object.prototype.hasOwnProperty.call(value, key))
				{
					var result = _Json_runHelp(decoder.b, value[key]);
					if (!$elm$core$Result$isOk(result))
					{
						return $elm$core$Result$Err(A2($elm$json$Json$Decode$Field, key, result.a));
					}
					keyValuePairs = _List_Cons(_Utils_Tuple2(key, result.a), keyValuePairs);
				}
			}
			return $elm$core$Result$Ok($elm$core$List$reverse(keyValuePairs));

		case 9:
			var answer = decoder.f;
			var decoders = decoder.g;
			for (var i = 0; i < decoders.length; i++)
			{
				var result = _Json_runHelp(decoders[i], value);
				if (!$elm$core$Result$isOk(result))
				{
					return result;
				}
				answer = answer(result.a);
			}
			return $elm$core$Result$Ok(answer);

		case 10:
			var result = _Json_runHelp(decoder.b, value);
			return (!$elm$core$Result$isOk(result))
				? result
				: _Json_runHelp(decoder.h(result.a), value);

		case 11:
			var errors = _List_Nil;
			for (var temp = decoder.g; temp.b; temp = temp.b) // WHILE_CONS
			{
				var result = _Json_runHelp(temp.a, value);
				if ($elm$core$Result$isOk(result))
				{
					return result;
				}
				errors = _List_Cons(result.a, errors);
			}
			return $elm$core$Result$Err($elm$json$Json$Decode$OneOf($elm$core$List$reverse(errors)));

		case 1:
			return $elm$core$Result$Err(A2($elm$json$Json$Decode$Failure, decoder.a, _Json_wrap(value)));

		case 0:
			return $elm$core$Result$Ok(decoder.a);
	}
}

function _Json_runArrayDecoder(decoder, value, toElmValue)
{
	var len = value.length;
	var array = new Array(len);
	for (var i = 0; i < len; i++)
	{
		var result = _Json_runHelp(decoder, value[i]);
		if (!$elm$core$Result$isOk(result))
		{
			return $elm$core$Result$Err(A2($elm$json$Json$Decode$Index, i, result.a));
		}
		array[i] = result.a;
	}
	return $elm$core$Result$Ok(toElmValue(array));
}

function _Json_isArray(value)
{
	return Array.isArray(value) || (typeof FileList !== 'undefined' && value instanceof FileList);
}

function _Json_toElmArray(array)
{
	return A2($elm$core$Array$initialize, array.length, function(i) { return array[i]; });
}

function _Json_expecting(type, value)
{
	return $elm$core$Result$Err(A2($elm$json$Json$Decode$Failure, 'Expecting ' + type, _Json_wrap(value)));
}


// EQUALITY

function _Json_equality(x, y)
{
	if (x === y)
	{
		return true;
	}

	if (x.$ !== y.$)
	{
		return false;
	}

	switch (x.$)
	{
		case 0:
		case 1:
			return x.a === y.a;

		case 2:
			return x.b === y.b;

		case 5:
			return x.c === y.c;

		case 3:
		case 4:
		case 8:
			return _Json_equality(x.b, y.b);

		case 6:
			return x.d === y.d && _Json_equality(x.b, y.b);

		case 7:
			return x.e === y.e && _Json_equality(x.b, y.b);

		case 9:
			return x.f === y.f && _Json_listEquality(x.g, y.g);

		case 10:
			return x.h === y.h && _Json_equality(x.b, y.b);

		case 11:
			return _Json_listEquality(x.g, y.g);
	}
}

function _Json_listEquality(aDecoders, bDecoders)
{
	var len = aDecoders.length;
	if (len !== bDecoders.length)
	{
		return false;
	}
	for (var i = 0; i < len; i++)
	{
		if (!_Json_equality(aDecoders[i], bDecoders[i]))
		{
			return false;
		}
	}
	return true;
}


// ENCODE

var _Json_encode = F2(function(indentLevel, value)
{
	return JSON.stringify(_Json_unwrap(value), null, indentLevel) + '';
});

function _Json_wrap_UNUSED(value) { return { $: 0, a: value }; }
function _Json_unwrap_UNUSED(value) { return value.a; }

function _Json_wrap(value) { return value; }
function _Json_unwrap(value) { return value; }

function _Json_emptyArray() { return []; }
function _Json_emptyObject() { return {}; }

var _Json_addField = F3(function(key, value, object)
{
	var unwrapped = _Json_unwrap(value);
	if (!(key === 'toJSON' && typeof unwrapped === 'function'))
	{
		object[key] = unwrapped;
	}
	return object;
});

function _Json_addEntry(func)
{
	return F2(function(entry, array)
	{
		array.push(_Json_unwrap(func(entry)));
		return array;
	});
}

var _Json_encodeNull = _Json_wrap(null);



// TASKS

function _Scheduler_succeed(value)
{
	return {
		$: 0,
		a: value
	};
}

function _Scheduler_fail(error)
{
	return {
		$: 1,
		a: error
	};
}

function _Scheduler_binding(callback)
{
	return {
		$: 2,
		b: callback,
		c: null
	};
}

var _Scheduler_andThen = F2(function(callback, task)
{
	return {
		$: 3,
		b: callback,
		d: task
	};
});

var _Scheduler_onError = F2(function(callback, task)
{
	return {
		$: 4,
		b: callback,
		d: task
	};
});

function _Scheduler_receive(callback)
{
	return {
		$: 5,
		b: callback
	};
}


// PROCESSES

var _Scheduler_guid = 0;

function _Scheduler_rawSpawn(task)
{
	var proc = {
		$: 0,
		e: _Scheduler_guid++,
		f: task,
		g: null,
		h: []
	};

	_Scheduler_enqueue(proc);

	return proc;
}

function _Scheduler_spawn(task)
{
	return _Scheduler_binding(function(callback) {
		callback(_Scheduler_succeed(_Scheduler_rawSpawn(task)));
	});
}

function _Scheduler_rawSend(proc, msg)
{
	proc.h.push(msg);
	_Scheduler_enqueue(proc);
}

var _Scheduler_send = F2(function(proc, msg)
{
	return _Scheduler_binding(function(callback) {
		_Scheduler_rawSend(proc, msg);
		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
});

function _Scheduler_kill(proc)
{
	return _Scheduler_binding(function(callback) {
		var task = proc.f;
		if (task.$ === 2 && task.c)
		{
			task.c();
		}

		proc.f = null;

		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
}


/* STEP PROCESSES

type alias Process =
  { $ : tag
  , id : unique_id
  , root : Task
  , stack : null | { $: SUCCEED | FAIL, a: callback, b: stack }
  , mailbox : [msg]
  }

*/


var _Scheduler_working = false;
var _Scheduler_queue = [];


function _Scheduler_enqueue(proc)
{
	_Scheduler_queue.push(proc);
	if (_Scheduler_working)
	{
		return;
	}
	_Scheduler_working = true;
	while (proc = _Scheduler_queue.shift())
	{
		_Scheduler_step(proc);
	}
	_Scheduler_working = false;
}


function _Scheduler_step(proc)
{
	while (proc.f)
	{
		var rootTag = proc.f.$;
		if (rootTag === 0 || rootTag === 1)
		{
			while (proc.g && proc.g.$ !== rootTag)
			{
				proc.g = proc.g.i;
			}
			if (!proc.g)
			{
				return;
			}
			proc.f = proc.g.b(proc.f.a);
			proc.g = proc.g.i;
		}
		else if (rootTag === 2)
		{
			proc.f.c = proc.f.b(function(newRoot) {
				proc.f = newRoot;
				_Scheduler_enqueue(proc);
			});
			return;
		}
		else if (rootTag === 5)
		{
			if (proc.h.length === 0)
			{
				return;
			}
			proc.f = proc.f.b(proc.h.shift());
		}
		else // if (rootTag === 3 || rootTag === 4)
		{
			proc.g = {
				$: rootTag === 3 ? 0 : 1,
				b: proc.f.b,
				i: proc.g
			};
			proc.f = proc.f.d;
		}
	}
}



function _Process_sleep(time)
{
	return _Scheduler_binding(function(callback) {
		var id = setTimeout(function() {
			callback(_Scheduler_succeed(_Utils_Tuple0));
		}, time);

		return function() { clearTimeout(id); };
	});
}




// PROGRAMS


var _Platform_worker = F4(function(impl, flagDecoder, debugMetadata, args)
{
	return _Platform_initialize(
		flagDecoder,
		args,
		impl.dy,
		impl.d9,
		impl.dX,
		function() { return function() {} }
	);
});



// INITIALIZE A PROGRAM


function _Platform_initialize(flagDecoder, args, init, update, subscriptions, stepperBuilder)
{
	var result = A2(_Json_run, flagDecoder, _Json_wrap(args ? args['flags'] : undefined));
	$elm$core$Result$isOk(result) || _Debug_crash(2 /**_UNUSED/, _Json_errorToString(result.a) /**/);
	var managers = {};
	var initPair = init(result.a);
	var model = initPair.a;
	var stepper = stepperBuilder(sendToApp, model);
	var ports = _Platform_setupEffects(managers, sendToApp);

	function sendToApp(msg, viewMetadata)
	{
		var pair = A2(update, msg, model);
		stepper(model = pair.a, viewMetadata);
		_Platform_enqueueEffects(managers, pair.b, subscriptions(model));
	}

	_Platform_enqueueEffects(managers, initPair.b, subscriptions(model));

	return ports ? { ports: ports } : {};
}



// TRACK PRELOADS
//
// This is used by code in elm/browser and elm/http
// to register any HTTP requests that are triggered by init.
//


var _Platform_preload;


function _Platform_registerPreload(url)
{
	_Platform_preload.add(url);
}



// EFFECT MANAGERS


var _Platform_effectManagers = {};


function _Platform_setupEffects(managers, sendToApp)
{
	var ports;

	// setup all necessary effect managers
	for (var key in _Platform_effectManagers)
	{
		var manager = _Platform_effectManagers[key];

		if (manager.a)
		{
			ports = ports || {};
			ports[key] = manager.a(key, sendToApp);
		}

		managers[key] = _Platform_instantiateManager(manager, sendToApp);
	}

	return ports;
}


function _Platform_createManager(init, onEffects, onSelfMsg, cmdMap, subMap)
{
	return {
		b: init,
		c: onEffects,
		d: onSelfMsg,
		e: cmdMap,
		f: subMap
	};
}


function _Platform_instantiateManager(info, sendToApp)
{
	var router = {
		g: sendToApp,
		h: undefined
	};

	var onEffects = info.c;
	var onSelfMsg = info.d;
	var cmdMap = info.e;
	var subMap = info.f;

	function loop(state)
	{
		return A2(_Scheduler_andThen, loop, _Scheduler_receive(function(msg)
		{
			var value = msg.a;

			if (msg.$ === 0)
			{
				return A3(onSelfMsg, router, value, state);
			}

			return cmdMap && subMap
				? A4(onEffects, router, value.i, value.j, state)
				: A3(onEffects, router, cmdMap ? value.i : value.j, state);
		}));
	}

	return router.h = _Scheduler_rawSpawn(A2(_Scheduler_andThen, loop, info.b));
}



// ROUTING


var _Platform_sendToApp = F2(function(router, msg)
{
	return _Scheduler_binding(function(callback)
	{
		router.g(msg);
		callback(_Scheduler_succeed(_Utils_Tuple0));
	});
});


var _Platform_sendToSelf = F2(function(router, msg)
{
	return A2(_Scheduler_send, router.h, {
		$: 0,
		a: msg
	});
});



// BAGS


function _Platform_leaf(home)
{
	return function(value)
	{
		return {
			$: 1,
			k: home,
			l: value
		};
	};
}


function _Platform_batch(list)
{
	return {
		$: 2,
		m: list
	};
}


var _Platform_map = F2(function(tagger, bag)
{
	return {
		$: 3,
		n: tagger,
		o: bag
	}
});



// PIPE BAGS INTO EFFECT MANAGERS
//
// Effects must be queued!
//
// Say your init contains a synchronous command, like Time.now or Time.here
//
//   - This will produce a batch of effects (FX_1)
//   - The synchronous task triggers the subsequent `update` call
//   - This will produce a batch of effects (FX_2)
//
// If we just start dispatching FX_2, subscriptions from FX_2 can be processed
// before subscriptions from FX_1. No good! Earlier versions of this code had
// this problem, leading to these reports:
//
//   https://github.com/elm/core/issues/980
//   https://github.com/elm/core/pull/981
//   https://github.com/elm/compiler/issues/1776
//
// The queue is necessary to avoid ordering issues for synchronous commands.


// Why use true/false here? Why not just check the length of the queue?
// The goal is to detect "are we currently dispatching effects?" If we
// are, we need to bail and let the ongoing while loop handle things.
//
// Now say the queue has 1 element. When we dequeue the final element,
// the queue will be empty, but we are still actively dispatching effects.
// So you could get queue jumping in a really tricky category of cases.
//
var _Platform_effectsQueue = [];
var _Platform_effectsActive = false;


function _Platform_enqueueEffects(managers, cmdBag, subBag)
{
	_Platform_effectsQueue.push({ p: managers, q: cmdBag, r: subBag });

	if (_Platform_effectsActive) return;

	_Platform_effectsActive = true;
	for (var fx; fx = _Platform_effectsQueue.shift(); )
	{
		_Platform_dispatchEffects(fx.p, fx.q, fx.r);
	}
	_Platform_effectsActive = false;
}


function _Platform_dispatchEffects(managers, cmdBag, subBag)
{
	var effectsDict = {};
	_Platform_gatherEffects(true, cmdBag, effectsDict, null);
	_Platform_gatherEffects(false, subBag, effectsDict, null);

	for (var home in managers)
	{
		_Scheduler_rawSend(managers[home], {
			$: 'fx',
			a: effectsDict[home] || { i: _List_Nil, j: _List_Nil }
		});
	}
}


function _Platform_gatherEffects(isCmd, bag, effectsDict, taggers)
{
	switch (bag.$)
	{
		case 1:
			var home = bag.k;
			var effect = _Platform_toEffect(isCmd, home, taggers, bag.l);
			effectsDict[home] = _Platform_insert(isCmd, effect, effectsDict[home]);
			return;

		case 2:
			for (var list = bag.m; list.b; list = list.b) // WHILE_CONS
			{
				_Platform_gatherEffects(isCmd, list.a, effectsDict, taggers);
			}
			return;

		case 3:
			_Platform_gatherEffects(isCmd, bag.o, effectsDict, {
				s: bag.n,
				t: taggers
			});
			return;
	}
}


function _Platform_toEffect(isCmd, home, taggers, value)
{
	function applyTaggers(x)
	{
		for (var temp = taggers; temp; temp = temp.t)
		{
			x = temp.s(x);
		}
		return x;
	}

	var map = isCmd
		? _Platform_effectManagers[home].e
		: _Platform_effectManagers[home].f;

	return A2(map, applyTaggers, value)
}


function _Platform_insert(isCmd, newEffect, effects)
{
	effects = effects || { i: _List_Nil, j: _List_Nil };

	isCmd
		? (effects.i = _List_Cons(newEffect, effects.i))
		: (effects.j = _List_Cons(newEffect, effects.j));

	return effects;
}



// PORTS


function _Platform_checkPortName(name)
{
	if (_Platform_effectManagers[name])
	{
		_Debug_crash(3, name)
	}
}



// OUTGOING PORTS


function _Platform_outgoingPort(name, converter)
{
	_Platform_checkPortName(name);
	_Platform_effectManagers[name] = {
		e: _Platform_outgoingPortMap,
		u: converter,
		a: _Platform_setupOutgoingPort
	};
	return _Platform_leaf(name);
}


var _Platform_outgoingPortMap = F2(function(tagger, value) { return value; });


function _Platform_setupOutgoingPort(name)
{
	var subs = [];
	var converter = _Platform_effectManagers[name].u;

	// CREATE MANAGER

	var init = _Process_sleep(0);

	_Platform_effectManagers[name].b = init;
	_Platform_effectManagers[name].c = F3(function(router, cmdList, state)
	{
		for ( ; cmdList.b; cmdList = cmdList.b) // WHILE_CONS
		{
			// grab a separate reference to subs in case unsubscribe is called
			var currentSubs = subs;
			var value = _Json_unwrap(converter(cmdList.a));
			for (var i = 0; i < currentSubs.length; i++)
			{
				currentSubs[i](value);
			}
		}
		return init;
	});

	// PUBLIC API

	function subscribe(callback)
	{
		subs.push(callback);
	}

	function unsubscribe(callback)
	{
		// copy subs into a new array in case unsubscribe is called within a
		// subscribed callback
		subs = subs.slice();
		var index = subs.indexOf(callback);
		if (index >= 0)
		{
			subs.splice(index, 1);
		}
	}

	return {
		subscribe: subscribe,
		unsubscribe: unsubscribe
	};
}



// INCOMING PORTS


function _Platform_incomingPort(name, converter)
{
	_Platform_checkPortName(name);
	_Platform_effectManagers[name] = {
		f: _Platform_incomingPortMap,
		u: converter,
		a: _Platform_setupIncomingPort
	};
	return _Platform_leaf(name);
}


var _Platform_incomingPortMap = F2(function(tagger, finalTagger)
{
	return function(value)
	{
		return tagger(finalTagger(value));
	};
});


function _Platform_setupIncomingPort(name, sendToApp)
{
	var subs = _List_Nil;
	var converter = _Platform_effectManagers[name].u;

	// CREATE MANAGER

	var init = _Scheduler_succeed(null);

	_Platform_effectManagers[name].b = init;
	_Platform_effectManagers[name].c = F3(function(router, subList, state)
	{
		subs = subList;
		return init;
	});

	// PUBLIC API

	function send(incomingValue)
	{
		var result = A2(_Json_run, converter, _Json_wrap(incomingValue));

		$elm$core$Result$isOk(result) || _Debug_crash(4, name, result.a);

		var value = result.a;
		for (var temp = subs; temp.b; temp = temp.b) // WHILE_CONS
		{
			sendToApp(temp.a(value));
		}
	}

	return { send: send };
}



// EXPORT ELM MODULES
//
// Have DEBUG and PROD versions so that we can (1) give nicer errors in
// debug mode and (2) not pay for the bits needed for that in prod mode.
//


function _Platform_export(exports)
{
	scope['Elm']
		? _Platform_mergeExportsProd(scope['Elm'], exports)
		: scope['Elm'] = exports;
}


function _Platform_mergeExportsProd(obj, exports)
{
	for (var name in exports)
	{
		(name in obj)
			? (name == 'init')
				? _Debug_crash(6)
				: _Platform_mergeExportsProd(obj[name], exports[name])
			: (obj[name] = exports[name]);
	}
}


function _Platform_export_UNUSED(exports)
{
	scope['Elm']
		? _Platform_mergeExportsDebug('Elm', scope['Elm'], exports)
		: scope['Elm'] = exports;
}


function _Platform_mergeExportsDebug(moduleName, obj, exports)
{
	for (var name in exports)
	{
		(name in obj)
			? (name == 'init')
				? _Debug_crash(6, moduleName)
				: _Platform_mergeExportsDebug(moduleName + '.' + name, obj[name], exports[name])
			: (obj[name] = exports[name]);
	}
}




// HELPERS


var _VirtualDom_divertHrefToApp;

var _VirtualDom_doc = typeof document !== 'undefined' ? document : {};


function _VirtualDom_appendChild(parent, child)
{
	parent.appendChild(child);
}

var _VirtualDom_init = F4(function(virtualNode, flagDecoder, debugMetadata, args)
{
	// NOTE: this function needs _Platform_export available to work

	/**/
	var node = args['node'];
	//*/
	/**_UNUSED/
	var node = args && args['node'] ? args['node'] : _Debug_crash(0);
	//*/

	node.parentNode.replaceChild(
		_VirtualDom_render(virtualNode, function() {}),
		node
	);

	return {};
});



// TEXT


function _VirtualDom_text(string)
{
	return {
		$: 0,
		a: string
	};
}



// NODE


var _VirtualDom_nodeNS = F2(function(namespace, tag)
{
	return F2(function(factList, kidList)
	{
		for (var kids = [], descendantsCount = 0; kidList.b; kidList = kidList.b) // WHILE_CONS
		{
			var kid = kidList.a;
			descendantsCount += (kid.b || 0);
			kids.push(kid);
		}
		descendantsCount += kids.length;

		return {
			$: 1,
			c: tag,
			d: _VirtualDom_organizeFacts(factList),
			e: kids,
			f: namespace,
			b: descendantsCount
		};
	});
});


var _VirtualDom_node = _VirtualDom_nodeNS(undefined);



// KEYED NODE


var _VirtualDom_keyedNodeNS = F2(function(namespace, tag)
{
	return F2(function(factList, kidList)
	{
		for (var kids = [], descendantsCount = 0; kidList.b; kidList = kidList.b) // WHILE_CONS
		{
			var kid = kidList.a;
			descendantsCount += (kid.b.b || 0);
			kids.push(kid);
		}
		descendantsCount += kids.length;

		return {
			$: 2,
			c: tag,
			d: _VirtualDom_organizeFacts(factList),
			e: kids,
			f: namespace,
			b: descendantsCount
		};
	});
});


var _VirtualDom_keyedNode = _VirtualDom_keyedNodeNS(undefined);



// CUSTOM


function _VirtualDom_custom(factList, model, render, diff)
{
	return {
		$: 3,
		d: _VirtualDom_organizeFacts(factList),
		g: model,
		h: render,
		i: diff
	};
}



// MAP


var _VirtualDom_map = F2(function(tagger, node)
{
	return {
		$: 4,
		j: tagger,
		k: node,
		b: 1 + (node.b || 0)
	};
});



// LAZY


function _VirtualDom_thunk(refs, thunk)
{
	return {
		$: 5,
		l: refs,
		m: thunk,
		k: undefined
	};
}

var _VirtualDom_lazy = F2(function(func, a)
{
	return _VirtualDom_thunk([func, a], function() {
		return func(a);
	});
});

var _VirtualDom_lazy2 = F3(function(func, a, b)
{
	return _VirtualDom_thunk([func, a, b], function() {
		return A2(func, a, b);
	});
});

var _VirtualDom_lazy3 = F4(function(func, a, b, c)
{
	return _VirtualDom_thunk([func, a, b, c], function() {
		return A3(func, a, b, c);
	});
});

var _VirtualDom_lazy4 = F5(function(func, a, b, c, d)
{
	return _VirtualDom_thunk([func, a, b, c, d], function() {
		return A4(func, a, b, c, d);
	});
});

var _VirtualDom_lazy5 = F6(function(func, a, b, c, d, e)
{
	return _VirtualDom_thunk([func, a, b, c, d, e], function() {
		return A5(func, a, b, c, d, e);
	});
});

var _VirtualDom_lazy6 = F7(function(func, a, b, c, d, e, f)
{
	return _VirtualDom_thunk([func, a, b, c, d, e, f], function() {
		return A6(func, a, b, c, d, e, f);
	});
});

var _VirtualDom_lazy7 = F8(function(func, a, b, c, d, e, f, g)
{
	return _VirtualDom_thunk([func, a, b, c, d, e, f, g], function() {
		return A7(func, a, b, c, d, e, f, g);
	});
});

var _VirtualDom_lazy8 = F9(function(func, a, b, c, d, e, f, g, h)
{
	return _VirtualDom_thunk([func, a, b, c, d, e, f, g, h], function() {
		return A8(func, a, b, c, d, e, f, g, h);
	});
});



// FACTS


var _VirtualDom_on = F2(function(key, handler)
{
	return {
		$: 'a0',
		n: key,
		o: handler
	};
});
var _VirtualDom_style = F2(function(key, value)
{
	return {
		$: 'a1',
		n: key,
		o: value
	};
});
var _VirtualDom_property = F2(function(key, value)
{
	return {
		$: 'a2',
		n: key,
		o: value
	};
});
var _VirtualDom_attribute = F2(function(key, value)
{
	return {
		$: 'a3',
		n: key,
		o: value
	};
});
var _VirtualDom_attributeNS = F3(function(namespace, key, value)
{
	return {
		$: 'a4',
		n: key,
		o: { f: namespace, o: value }
	};
});



// XSS ATTACK VECTOR CHECKS
//
// For some reason, tabs can appear in href protocols and it still works.
// So '\tjava\tSCRIPT:alert("!!!")' and 'javascript:alert("!!!")' are the same
// in practice. That is why _VirtualDom_RE_js and _VirtualDom_RE_js_html look
// so freaky.
//
// Pulling the regular expressions out to the top level gives a slight speed
// boost in small benchmarks (4-10%) but hoisting values to reduce allocation
// can be unpredictable in large programs where JIT may have a harder time with
// functions are not fully self-contained. The benefit is more that the js and
// js_html ones are so weird that I prefer to see them near each other.


var _VirtualDom_RE_script = /^script$/i;
var _VirtualDom_RE_on_formAction = /^(on|formAction$)/i;
var _VirtualDom_RE_js = /^\s*j\s*a\s*v\s*a\s*s\s*c\s*r\s*i\s*p\s*t\s*:/i;
var _VirtualDom_RE_js_html = /^\s*(j\s*a\s*v\s*a\s*s\s*c\s*r\s*i\s*p\s*t\s*:|d\s*a\s*t\s*a\s*:\s*t\s*e\s*x\s*t\s*\/\s*h\s*t\s*m\s*l\s*(,|;))/i;


function _VirtualDom_noScript(tag)
{
	return _VirtualDom_RE_script.test(tag) ? 'p' : tag;
}

function _VirtualDom_noOnOrFormAction(key)
{
	return _VirtualDom_RE_on_formAction.test(key) ? 'data-' + key : key;
}

function _VirtualDom_noInnerHtmlOrFormAction(key)
{
	return key == 'innerHTML' || key == 'outerHTML' || key == 'formAction' ? 'data-' + key : key;
}

function _VirtualDom_noJavaScriptUri(value)
{
	return _VirtualDom_RE_js.test(value)
		? /**/''//*//**_UNUSED/'javascript:alert("This is an XSS vector. Please use ports or web components instead.")'//*/
		: value;
}

function _VirtualDom_noJavaScriptOrHtmlUri(value)
{
	return _VirtualDom_RE_js_html.test(value)
		? /**/''//*//**_UNUSED/'javascript:alert("This is an XSS vector. Please use ports or web components instead.")'//*/
		: value;
}

function _VirtualDom_noJavaScriptOrHtmlJson(value)
{
	return (
		(typeof _Json_unwrap(value) === 'string' && _VirtualDom_RE_js_html.test(_Json_unwrap(value)))
		||
		(Array.isArray(_Json_unwrap(value)) && _VirtualDom_RE_js_html.test(String(_Json_unwrap(value))))
	)
		? _Json_wrap(
			/**/''//*//**_UNUSED/'javascript:alert("This is an XSS vector. Please use ports or web components instead.")'//*/
		) : value;
}



// MAP FACTS


var _VirtualDom_mapAttribute = F2(function(func, attr)
{
	return (attr.$ === 'a0')
		? A2(_VirtualDom_on, attr.n, _VirtualDom_mapHandler(func, attr.o))
		: attr;
});

function _VirtualDom_mapHandler(func, handler)
{
	var tag = $elm$virtual_dom$VirtualDom$toHandlerInt(handler);

	// 0 = Normal
	// 1 = MayStopPropagation
	// 2 = MayPreventDefault
	// 3 = Custom

	return {
		$: handler.$,
		a:
			!tag
				? A2($elm$json$Json$Decode$map, func, handler.a)
				:
			A3($elm$json$Json$Decode$map2,
				tag < 3
					? _VirtualDom_mapEventTuple
					: _VirtualDom_mapEventRecord,
				$elm$json$Json$Decode$succeed(func),
				handler.a
			)
	};
}

var _VirtualDom_mapEventTuple = F2(function(func, tuple)
{
	return _Utils_Tuple2(func(tuple.a), tuple.b);
});

var _VirtualDom_mapEventRecord = F2(function(func, record)
{
	return {
		aA: func(record.aA),
		b2: record.b2,
		bR: record.bR
	}
});



// ORGANIZE FACTS


function _VirtualDom_organizeFacts(factList)
{
	for (var facts = {}; factList.b; factList = factList.b) // WHILE_CONS
	{
		var entry = factList.a;

		var tag = entry.$;
		var key = entry.n;
		var value = entry.o;

		if (tag === 'a2')
		{
			(key === 'className')
				? _VirtualDom_addClass(facts, key, _Json_unwrap(value))
				: facts[key] = _Json_unwrap(value);

			continue;
		}

		var subFacts = facts[tag] || (facts[tag] = {});
		(tag === 'a3' && key === 'class')
			? _VirtualDom_addClass(subFacts, key, value)
			: subFacts[key] = value;
	}

	return facts;
}

function _VirtualDom_addClass(object, key, newClass)
{
	var classes = object[key];
	object[key] = classes ? classes + ' ' + newClass : newClass;
}



// RENDER


function _VirtualDom_render(vNode, eventNode)
{
	var tag = vNode.$;

	if (tag === 5)
	{
		return _VirtualDom_render(vNode.k || (vNode.k = vNode.m()), eventNode);
	}

	if (tag === 0)
	{
		return _VirtualDom_doc.createTextNode(vNode.a);
	}

	if (tag === 4)
	{
		var subNode = vNode.k;
		var tagger = vNode.j;

		while (subNode.$ === 4)
		{
			typeof tagger !== 'object'
				? tagger = [tagger, subNode.j]
				: tagger.push(subNode.j);

			subNode = subNode.k;
		}

		var subEventRoot = { j: tagger, p: eventNode };
		var domNode = _VirtualDom_render(subNode, subEventRoot);
		domNode.elm_event_node_ref = subEventRoot;
		return domNode;
	}

	if (tag === 3)
	{
		var domNode = vNode.h(vNode.g);
		_VirtualDom_applyFacts(domNode, eventNode, vNode.d);
		return domNode;
	}

	// at this point `tag` must be 1 or 2

	var domNode = vNode.f
		? _VirtualDom_doc.createElementNS(vNode.f, vNode.c)
		: _VirtualDom_doc.createElement(vNode.c);

	if (_VirtualDom_divertHrefToApp && vNode.c == 'a')
	{
		domNode.addEventListener('click', _VirtualDom_divertHrefToApp(domNode));
	}

	_VirtualDom_applyFacts(domNode, eventNode, vNode.d);

	for (var kids = vNode.e, i = 0; i < kids.length; i++)
	{
		_VirtualDom_appendChild(domNode, _VirtualDom_render(tag === 1 ? kids[i] : kids[i].b, eventNode));
	}

	return domNode;
}



// APPLY FACTS


function _VirtualDom_applyFacts(domNode, eventNode, facts)
{
	for (var key in facts)
	{
		var value = facts[key];

		key === 'a1'
			? _VirtualDom_applyStyles(domNode, value)
			:
		key === 'a0'
			? _VirtualDom_applyEvents(domNode, eventNode, value)
			:
		key === 'a3'
			? _VirtualDom_applyAttrs(domNode, value)
			:
		key === 'a4'
			? _VirtualDom_applyAttrsNS(domNode, value)
			:
		((key !== 'value' && key !== 'checked') || domNode[key] !== value) && (domNode[key] = value);
	}
}



// APPLY STYLES


function _VirtualDom_applyStyles(domNode, styles)
{
	var domNodeStyle = domNode.style;

	for (var key in styles)
	{
		domNodeStyle[key] = styles[key];
	}
}



// APPLY ATTRS


function _VirtualDom_applyAttrs(domNode, attrs)
{
	for (var key in attrs)
	{
		var value = attrs[key];
		typeof value !== 'undefined'
			? domNode.setAttribute(key, value)
			: domNode.removeAttribute(key);
	}
}



// APPLY NAMESPACED ATTRS


function _VirtualDom_applyAttrsNS(domNode, nsAttrs)
{
	for (var key in nsAttrs)
	{
		var pair = nsAttrs[key];
		var namespace = pair.f;
		var value = pair.o;

		typeof value !== 'undefined'
			? domNode.setAttributeNS(namespace, key, value)
			: domNode.removeAttributeNS(namespace, key);
	}
}



// APPLY EVENTS


function _VirtualDom_applyEvents(domNode, eventNode, events)
{
	var allCallbacks = domNode.elmFs || (domNode.elmFs = {});

	for (var key in events)
	{
		var newHandler = events[key];
		var oldCallback = allCallbacks[key];

		if (!newHandler)
		{
			domNode.removeEventListener(key, oldCallback);
			allCallbacks[key] = undefined;
			continue;
		}

		if (oldCallback)
		{
			var oldHandler = oldCallback.q;
			if (oldHandler.$ === newHandler.$)
			{
				oldCallback.q = newHandler;
				continue;
			}
			domNode.removeEventListener(key, oldCallback);
		}

		oldCallback = _VirtualDom_makeCallback(eventNode, newHandler);
		domNode.addEventListener(key, oldCallback,
			_VirtualDom_passiveSupported
			&& { passive: $elm$virtual_dom$VirtualDom$toHandlerInt(newHandler) < 2 }
		);
		allCallbacks[key] = oldCallback;
	}
}



// PASSIVE EVENTS


var _VirtualDom_passiveSupported;

try
{
	window.addEventListener('t', null, Object.defineProperty({}, 'passive', {
		get: function() { _VirtualDom_passiveSupported = true; }
	}));
}
catch(e) {}



// EVENT HANDLERS


function _VirtualDom_makeCallback(eventNode, initialHandler)
{
	function callback(event)
	{
		var handler = callback.q;
		var result = _Json_runHelp(handler.a, event);

		if (!$elm$core$Result$isOk(result))
		{
			return;
		}

		var tag = $elm$virtual_dom$VirtualDom$toHandlerInt(handler);

		// 0 = Normal
		// 1 = MayStopPropagation
		// 2 = MayPreventDefault
		// 3 = Custom

		var value = result.a;
		var message = !tag ? value : tag < 3 ? value.a : value.aA;
		var stopPropagation = tag == 1 ? value.b : tag == 3 && value.b2;
		var currentEventNode = (
			stopPropagation && event.stopPropagation(),
			(tag == 2 ? value.b : tag == 3 && value.bR) && event.preventDefault(),
			eventNode
		);
		var tagger;
		var i;
		while (tagger = currentEventNode.j)
		{
			if (typeof tagger == 'function')
			{
				message = tagger(message);
			}
			else
			{
				for (var i = tagger.length; i--; )
				{
					message = tagger[i](message);
				}
			}
			currentEventNode = currentEventNode.p;
		}
		currentEventNode(message, stopPropagation); // stopPropagation implies isSync
	}

	callback.q = initialHandler;

	return callback;
}

function _VirtualDom_equalEvents(x, y)
{
	return x.$ == y.$ && _Json_equality(x.a, y.a);
}



// DIFF


// TODO: Should we do patches like in iOS?
//
// type Patch
//   = At Int Patch
//   | Batch (List Patch)
//   | Change ...
//
// How could it not be better?
//
function _VirtualDom_diff(x, y)
{
	var patches = [];
	_VirtualDom_diffHelp(x, y, patches, 0);
	return patches;
}


function _VirtualDom_pushPatch(patches, type, index, data)
{
	var patch = {
		$: type,
		r: index,
		s: data,
		t: undefined,
		u: undefined
	};
	patches.push(patch);
	return patch;
}


function _VirtualDom_diffHelp(x, y, patches, index)
{
	if (x === y)
	{
		return;
	}

	var xType = x.$;
	var yType = y.$;

	// Bail if you run into different types of nodes. Implies that the
	// structure has changed significantly and it's not worth a diff.
	if (xType !== yType)
	{
		if (xType === 1 && yType === 2)
		{
			y = _VirtualDom_dekey(y);
			yType = 1;
		}
		else
		{
			_VirtualDom_pushPatch(patches, 0, index, y);
			return;
		}
	}

	// Now we know that both nodes are the same $.
	switch (yType)
	{
		case 5:
			var xRefs = x.l;
			var yRefs = y.l;
			var i = xRefs.length;
			var same = i === yRefs.length;
			while (same && i--)
			{
				same = xRefs[i] === yRefs[i];
			}
			if (same)
			{
				y.k = x.k;
				return;
			}
			y.k = y.m();
			var subPatches = [];
			_VirtualDom_diffHelp(x.k, y.k, subPatches, 0);
			subPatches.length > 0 && _VirtualDom_pushPatch(patches, 1, index, subPatches);
			return;

		case 4:
			// gather nested taggers
			var xTaggers = x.j;
			var yTaggers = y.j;
			var nesting = false;

			var xSubNode = x.k;
			while (xSubNode.$ === 4)
			{
				nesting = true;

				typeof xTaggers !== 'object'
					? xTaggers = [xTaggers, xSubNode.j]
					: xTaggers.push(xSubNode.j);

				xSubNode = xSubNode.k;
			}

			var ySubNode = y.k;
			while (ySubNode.$ === 4)
			{
				nesting = true;

				typeof yTaggers !== 'object'
					? yTaggers = [yTaggers, ySubNode.j]
					: yTaggers.push(ySubNode.j);

				ySubNode = ySubNode.k;
			}

			// Just bail if different numbers of taggers. This implies the
			// structure of the virtual DOM has changed.
			if (nesting && xTaggers.length !== yTaggers.length)
			{
				_VirtualDom_pushPatch(patches, 0, index, y);
				return;
			}

			// check if taggers are "the same"
			if (nesting ? !_VirtualDom_pairwiseRefEqual(xTaggers, yTaggers) : xTaggers !== yTaggers)
			{
				_VirtualDom_pushPatch(patches, 2, index, yTaggers);
			}

			// diff everything below the taggers
			_VirtualDom_diffHelp(xSubNode, ySubNode, patches, index + 1);
			return;

		case 0:
			if (x.a !== y.a)
			{
				_VirtualDom_pushPatch(patches, 3, index, y.a);
			}
			return;

		case 1:
			_VirtualDom_diffNodes(x, y, patches, index, _VirtualDom_diffKids);
			return;

		case 2:
			_VirtualDom_diffNodes(x, y, patches, index, _VirtualDom_diffKeyedKids);
			return;

		case 3:
			if (x.h !== y.h)
			{
				_VirtualDom_pushPatch(patches, 0, index, y);
				return;
			}

			var factsDiff = _VirtualDom_diffFacts(x.d, y.d);
			factsDiff && _VirtualDom_pushPatch(patches, 4, index, factsDiff);

			var patch = y.i(x.g, y.g);
			patch && _VirtualDom_pushPatch(patches, 5, index, patch);

			return;
	}
}

// assumes the incoming arrays are the same length
function _VirtualDom_pairwiseRefEqual(as, bs)
{
	for (var i = 0; i < as.length; i++)
	{
		if (as[i] !== bs[i])
		{
			return false;
		}
	}

	return true;
}

function _VirtualDom_diffNodes(x, y, patches, index, diffKids)
{
	// Bail if obvious indicators have changed. Implies more serious
	// structural changes such that it's not worth it to diff.
	if (x.c !== y.c || x.f !== y.f)
	{
		_VirtualDom_pushPatch(patches, 0, index, y);
		return;
	}

	var factsDiff = _VirtualDom_diffFacts(x.d, y.d);
	factsDiff && _VirtualDom_pushPatch(patches, 4, index, factsDiff);

	diffKids(x, y, patches, index);
}



// DIFF FACTS


// TODO Instead of creating a new diff object, it's possible to just test if
// there *is* a diff. During the actual patch, do the diff again and make the
// modifications directly. This way, there's no new allocations. Worth it?
function _VirtualDom_diffFacts(x, y, category)
{
	var diff;

	// look for changes and removals
	for (var xKey in x)
	{
		if (xKey === 'a1' || xKey === 'a0' || xKey === 'a3' || xKey === 'a4')
		{
			var subDiff = _VirtualDom_diffFacts(x[xKey], y[xKey] || {}, xKey);
			if (subDiff)
			{
				diff = diff || {};
				diff[xKey] = subDiff;
			}
			continue;
		}

		// remove if not in the new facts
		if (!(xKey in y))
		{
			diff = diff || {};
			diff[xKey] =
				!category
					? (typeof x[xKey] === 'string' ? '' : null)
					:
				(category === 'a1')
					? ''
					:
				(category === 'a0' || category === 'a3')
					? undefined
					:
				{ f: x[xKey].f, o: undefined };

			continue;
		}

		var xValue = x[xKey];
		var yValue = y[xKey];

		// reference equal, so don't worry about it
		if (xValue === yValue && xKey !== 'value' && xKey !== 'checked'
			|| category === 'a0' && _VirtualDom_equalEvents(xValue, yValue))
		{
			continue;
		}

		diff = diff || {};
		diff[xKey] = yValue;
	}

	// add new stuff
	for (var yKey in y)
	{
		if (!(yKey in x))
		{
			diff = diff || {};
			diff[yKey] = y[yKey];
		}
	}

	return diff;
}



// DIFF KIDS


function _VirtualDom_diffKids(xParent, yParent, patches, index)
{
	var xKids = xParent.e;
	var yKids = yParent.e;

	var xLen = xKids.length;
	var yLen = yKids.length;

	// FIGURE OUT IF THERE ARE INSERTS OR REMOVALS

	if (xLen > yLen)
	{
		_VirtualDom_pushPatch(patches, 6, index, {
			v: yLen,
			i: xLen - yLen
		});
	}
	else if (xLen < yLen)
	{
		_VirtualDom_pushPatch(patches, 7, index, {
			v: xLen,
			e: yKids
		});
	}

	// PAIRWISE DIFF EVERYTHING ELSE

	for (var minLen = xLen < yLen ? xLen : yLen, i = 0; i < minLen; i++)
	{
		var xKid = xKids[i];
		_VirtualDom_diffHelp(xKid, yKids[i], patches, ++index);
		index += xKid.b || 0;
	}
}



// KEYED DIFF


function _VirtualDom_diffKeyedKids(xParent, yParent, patches, rootIndex)
{
	var localPatches = [];

	var changes = {}; // Dict String Entry
	var inserts = []; // Array { index : Int, entry : Entry }
	// type Entry = { tag : String, vnode : VNode, index : Int, data : _ }

	var xKids = xParent.e;
	var yKids = yParent.e;
	var xLen = xKids.length;
	var yLen = yKids.length;
	var xIndex = 0;
	var yIndex = 0;

	var index = rootIndex;

	while (xIndex < xLen && yIndex < yLen)
	{
		var x = xKids[xIndex];
		var y = yKids[yIndex];

		var xKey = x.a;
		var yKey = y.a;
		var xNode = x.b;
		var yNode = y.b;

		var newMatch = undefined;
		var oldMatch = undefined;

		// check if keys match

		if (xKey === yKey)
		{
			index++;
			_VirtualDom_diffHelp(xNode, yNode, localPatches, index);
			index += xNode.b || 0;

			xIndex++;
			yIndex++;
			continue;
		}

		// look ahead 1 to detect insertions and removals.

		var xNext = xKids[xIndex + 1];
		var yNext = yKids[yIndex + 1];

		if (xNext)
		{
			var xNextKey = xNext.a;
			var xNextNode = xNext.b;
			oldMatch = yKey === xNextKey;
		}

		if (yNext)
		{
			var yNextKey = yNext.a;
			var yNextNode = yNext.b;
			newMatch = xKey === yNextKey;
		}


		// swap x and y
		if (newMatch && oldMatch)
		{
			index++;
			_VirtualDom_diffHelp(xNode, yNextNode, localPatches, index);
			_VirtualDom_insertNode(changes, localPatches, xKey, yNode, yIndex, inserts);
			index += xNode.b || 0;

			index++;
			_VirtualDom_removeNode(changes, localPatches, xKey, xNextNode, index);
			index += xNextNode.b || 0;

			xIndex += 2;
			yIndex += 2;
			continue;
		}

		// insert y
		if (newMatch)
		{
			index++;
			_VirtualDom_insertNode(changes, localPatches, yKey, yNode, yIndex, inserts);
			_VirtualDom_diffHelp(xNode, yNextNode, localPatches, index);
			index += xNode.b || 0;

			xIndex += 1;
			yIndex += 2;
			continue;
		}

		// remove x
		if (oldMatch)
		{
			index++;
			_VirtualDom_removeNode(changes, localPatches, xKey, xNode, index);
			index += xNode.b || 0;

			index++;
			_VirtualDom_diffHelp(xNextNode, yNode, localPatches, index);
			index += xNextNode.b || 0;

			xIndex += 2;
			yIndex += 1;
			continue;
		}

		// remove x, insert y
		if (xNext && xNextKey === yNextKey)
		{
			index++;
			_VirtualDom_removeNode(changes, localPatches, xKey, xNode, index);
			_VirtualDom_insertNode(changes, localPatches, yKey, yNode, yIndex, inserts);
			index += xNode.b || 0;

			index++;
			_VirtualDom_diffHelp(xNextNode, yNextNode, localPatches, index);
			index += xNextNode.b || 0;

			xIndex += 2;
			yIndex += 2;
			continue;
		}

		break;
	}

	// eat up any remaining nodes with removeNode and insertNode

	while (xIndex < xLen)
	{
		index++;
		var x = xKids[xIndex];
		var xNode = x.b;
		_VirtualDom_removeNode(changes, localPatches, x.a, xNode, index);
		index += xNode.b || 0;
		xIndex++;
	}

	while (yIndex < yLen)
	{
		var endInserts = endInserts || [];
		var y = yKids[yIndex];
		_VirtualDom_insertNode(changes, localPatches, y.a, y.b, undefined, endInserts);
		yIndex++;
	}

	if (localPatches.length > 0 || inserts.length > 0 || endInserts)
	{
		_VirtualDom_pushPatch(patches, 8, rootIndex, {
			w: localPatches,
			x: inserts,
			y: endInserts
		});
	}
}



// CHANGES FROM KEYED DIFF


var _VirtualDom_POSTFIX = '_elmW6BL';


function _VirtualDom_insertNode(changes, localPatches, key, vnode, yIndex, inserts)
{
	var entry = changes[key];

	// never seen this key before
	if (!entry)
	{
		entry = {
			c: 0,
			z: vnode,
			r: yIndex,
			s: undefined
		};

		inserts.push({ r: yIndex, A: entry });
		changes[key] = entry;

		return;
	}

	// this key was removed earlier, a match!
	if (entry.c === 1)
	{
		inserts.push({ r: yIndex, A: entry });

		entry.c = 2;
		var subPatches = [];
		_VirtualDom_diffHelp(entry.z, vnode, subPatches, entry.r);
		entry.r = yIndex;
		entry.s.s = {
			w: subPatches,
			A: entry
		};

		return;
	}

	// this key has already been inserted or moved, a duplicate!
	_VirtualDom_insertNode(changes, localPatches, key + _VirtualDom_POSTFIX, vnode, yIndex, inserts);
}


function _VirtualDom_removeNode(changes, localPatches, key, vnode, index)
{
	var entry = changes[key];

	// never seen this key before
	if (!entry)
	{
		var patch = _VirtualDom_pushPatch(localPatches, 9, index, undefined);

		changes[key] = {
			c: 1,
			z: vnode,
			r: index,
			s: patch
		};

		return;
	}

	// this key was inserted earlier, a match!
	if (entry.c === 0)
	{
		entry.c = 2;
		var subPatches = [];
		_VirtualDom_diffHelp(vnode, entry.z, subPatches, index);

		_VirtualDom_pushPatch(localPatches, 9, index, {
			w: subPatches,
			A: entry
		});

		return;
	}

	// this key has already been removed or moved, a duplicate!
	_VirtualDom_removeNode(changes, localPatches, key + _VirtualDom_POSTFIX, vnode, index);
}



// ADD DOM NODES
//
// Each DOM node has an "index" assigned in order of traversal. It is important
// to minimize our crawl over the actual DOM, so these indexes (along with the
// descendantsCount of virtual nodes) let us skip touching entire subtrees of
// the DOM if we know there are no patches there.


function _VirtualDom_addDomNodes(domNode, vNode, patches, eventNode)
{
	_VirtualDom_addDomNodesHelp(domNode, vNode, patches, 0, 0, vNode.b, eventNode);
}


// assumes `patches` is non-empty and indexes increase monotonically.
function _VirtualDom_addDomNodesHelp(domNode, vNode, patches, i, low, high, eventNode)
{
	var patch = patches[i];
	var index = patch.r;

	while (index === low)
	{
		var patchType = patch.$;

		if (patchType === 1)
		{
			_VirtualDom_addDomNodes(domNode, vNode.k, patch.s, eventNode);
		}
		else if (patchType === 8)
		{
			patch.t = domNode;
			patch.u = eventNode;

			var subPatches = patch.s.w;
			if (subPatches.length > 0)
			{
				_VirtualDom_addDomNodesHelp(domNode, vNode, subPatches, 0, low, high, eventNode);
			}
		}
		else if (patchType === 9)
		{
			patch.t = domNode;
			patch.u = eventNode;

			var data = patch.s;
			if (data)
			{
				data.A.s = domNode;
				var subPatches = data.w;
				if (subPatches.length > 0)
				{
					_VirtualDom_addDomNodesHelp(domNode, vNode, subPatches, 0, low, high, eventNode);
				}
			}
		}
		else
		{
			patch.t = domNode;
			patch.u = eventNode;
		}

		i++;

		if (!(patch = patches[i]) || (index = patch.r) > high)
		{
			return i;
		}
	}

	var tag = vNode.$;

	if (tag === 4)
	{
		var subNode = vNode.k;

		while (subNode.$ === 4)
		{
			subNode = subNode.k;
		}

		return _VirtualDom_addDomNodesHelp(domNode, subNode, patches, i, low + 1, high, domNode.elm_event_node_ref);
	}

	// tag must be 1 or 2 at this point

	var vKids = vNode.e;
	var childNodes = domNode.childNodes;
	for (var j = 0; j < vKids.length; j++)
	{
		low++;
		var vKid = tag === 1 ? vKids[j] : vKids[j].b;
		var nextLow = low + (vKid.b || 0);
		if (low <= index && index <= nextLow)
		{
			i = _VirtualDom_addDomNodesHelp(childNodes[j], vKid, patches, i, low, nextLow, eventNode);
			if (!(patch = patches[i]) || (index = patch.r) > high)
			{
				return i;
			}
		}
		low = nextLow;
	}
	return i;
}



// APPLY PATCHES


function _VirtualDom_applyPatches(rootDomNode, oldVirtualNode, patches, eventNode)
{
	if (patches.length === 0)
	{
		return rootDomNode;
	}

	_VirtualDom_addDomNodes(rootDomNode, oldVirtualNode, patches, eventNode);
	return _VirtualDom_applyPatchesHelp(rootDomNode, patches);
}

function _VirtualDom_applyPatchesHelp(rootDomNode, patches)
{
	for (var i = 0; i < patches.length; i++)
	{
		var patch = patches[i];
		var localDomNode = patch.t
		var newNode = _VirtualDom_applyPatch(localDomNode, patch);
		if (localDomNode === rootDomNode)
		{
			rootDomNode = newNode;
		}
	}
	return rootDomNode;
}

function _VirtualDom_applyPatch(domNode, patch)
{
	switch (patch.$)
	{
		case 0:
			return _VirtualDom_applyPatchRedraw(domNode, patch.s, patch.u);

		case 4:
			_VirtualDom_applyFacts(domNode, patch.u, patch.s);
			return domNode;

		case 3:
			domNode.replaceData(0, domNode.length, patch.s);
			return domNode;

		case 1:
			return _VirtualDom_applyPatchesHelp(domNode, patch.s);

		case 2:
			if (domNode.elm_event_node_ref)
			{
				domNode.elm_event_node_ref.j = patch.s;
			}
			else
			{
				domNode.elm_event_node_ref = { j: patch.s, p: patch.u };
			}
			return domNode;

		case 6:
			var data = patch.s;
			for (var i = 0; i < data.i; i++)
			{
				domNode.removeChild(domNode.childNodes[data.v]);
			}
			return domNode;

		case 7:
			var data = patch.s;
			var kids = data.e;
			var i = data.v;
			var theEnd = domNode.childNodes[i];
			for (; i < kids.length; i++)
			{
				domNode.insertBefore(_VirtualDom_render(kids[i], patch.u), theEnd);
			}
			return domNode;

		case 9:
			var data = patch.s;
			if (!data)
			{
				domNode.parentNode.removeChild(domNode);
				return domNode;
			}
			var entry = data.A;
			if (typeof entry.r !== 'undefined')
			{
				domNode.parentNode.removeChild(domNode);
			}
			entry.s = _VirtualDom_applyPatchesHelp(domNode, data.w);
			return domNode;

		case 8:
			return _VirtualDom_applyPatchReorder(domNode, patch);

		case 5:
			return patch.s(domNode);

		default:
			_Debug_crash(10); // 'Ran into an unknown patch!'
	}
}


function _VirtualDom_applyPatchRedraw(domNode, vNode, eventNode)
{
	var parentNode = domNode.parentNode;
	var newNode = _VirtualDom_render(vNode, eventNode);

	if (!newNode.elm_event_node_ref)
	{
		newNode.elm_event_node_ref = domNode.elm_event_node_ref;
	}

	if (parentNode && newNode !== domNode)
	{
		parentNode.replaceChild(newNode, domNode);
	}
	return newNode;
}


function _VirtualDom_applyPatchReorder(domNode, patch)
{
	var data = patch.s;

	// remove end inserts
	var frag = _VirtualDom_applyPatchReorderEndInsertsHelp(data.y, patch);

	// removals
	domNode = _VirtualDom_applyPatchesHelp(domNode, data.w);

	// inserts
	var inserts = data.x;
	for (var i = 0; i < inserts.length; i++)
	{
		var insert = inserts[i];
		var entry = insert.A;
		var node = entry.c === 2
			? entry.s
			: _VirtualDom_render(entry.z, patch.u);
		domNode.insertBefore(node, domNode.childNodes[insert.r]);
	}

	// add end inserts
	if (frag)
	{
		_VirtualDom_appendChild(domNode, frag);
	}

	return domNode;
}


function _VirtualDom_applyPatchReorderEndInsertsHelp(endInserts, patch)
{
	if (!endInserts)
	{
		return;
	}

	var frag = _VirtualDom_doc.createDocumentFragment();
	for (var i = 0; i < endInserts.length; i++)
	{
		var insert = endInserts[i];
		var entry = insert.A;
		_VirtualDom_appendChild(frag, entry.c === 2
			? entry.s
			: _VirtualDom_render(entry.z, patch.u)
		);
	}
	return frag;
}


function _VirtualDom_virtualize(node)
{
	// TEXT NODES

	if (node.nodeType === 3)
	{
		return _VirtualDom_text(node.textContent);
	}


	// WEIRD NODES

	if (node.nodeType !== 1)
	{
		return _VirtualDom_text('');
	}


	// ELEMENT NODES

	var attrList = _List_Nil;
	var attrs = node.attributes;
	for (var i = attrs.length; i--; )
	{
		var attr = attrs[i];
		var name = attr.name;
		var value = attr.value;
		attrList = _List_Cons( A2(_VirtualDom_attribute, name, value), attrList );
	}

	var tag = node.tagName.toLowerCase();
	var kidList = _List_Nil;
	var kids = node.childNodes;

	for (var i = kids.length; i--; )
	{
		kidList = _List_Cons(_VirtualDom_virtualize(kids[i]), kidList);
	}
	return A3(_VirtualDom_node, tag, attrList, kidList);
}

function _VirtualDom_dekey(keyedNode)
{
	var keyedKids = keyedNode.e;
	var len = keyedKids.length;
	var kids = new Array(len);
	for (var i = 0; i < len; i++)
	{
		kids[i] = keyedKids[i].b;
	}

	return {
		$: 1,
		c: keyedNode.c,
		d: keyedNode.d,
		e: kids,
		f: keyedNode.f,
		b: keyedNode.b
	};
}




// ELEMENT


var _Debugger_element;

var _Browser_element = _Debugger_element || F4(function(impl, flagDecoder, debugMetadata, args)
{
	return _Platform_initialize(
		flagDecoder,
		args,
		impl.dy,
		impl.d9,
		impl.dX,
		function(sendToApp, initialModel) {
			var view = impl.ea;
			/**/
			var domNode = args['node'];
			//*/
			/**_UNUSED/
			var domNode = args && args['node'] ? args['node'] : _Debug_crash(0);
			//*/
			var currNode = _VirtualDom_virtualize(domNode);

			return _Browser_makeAnimator(initialModel, function(model)
			{
				var nextNode = view(model);
				var patches = _VirtualDom_diff(currNode, nextNode);
				domNode = _VirtualDom_applyPatches(domNode, currNode, patches, sendToApp);
				currNode = nextNode;
			});
		}
	);
});



// DOCUMENT


var _Debugger_document;

var _Browser_document = _Debugger_document || F4(function(impl, flagDecoder, debugMetadata, args)
{
	return _Platform_initialize(
		flagDecoder,
		args,
		impl.dy,
		impl.d9,
		impl.dX,
		function(sendToApp, initialModel) {
			var divertHrefToApp = impl.bW && impl.bW(sendToApp)
			var view = impl.ea;
			var title = _VirtualDom_doc.title;
			var bodyNode = _VirtualDom_doc.body;
			var currNode = _VirtualDom_virtualize(bodyNode);
			return _Browser_makeAnimator(initialModel, function(model)
			{
				_VirtualDom_divertHrefToApp = divertHrefToApp;
				var doc = view(model);
				var nextNode = _VirtualDom_node('body')(_List_Nil)(doc.aZ);
				var patches = _VirtualDom_diff(currNode, nextNode);
				bodyNode = _VirtualDom_applyPatches(bodyNode, currNode, patches, sendToApp);
				currNode = nextNode;
				_VirtualDom_divertHrefToApp = 0;
				(title !== doc.d$) && (_VirtualDom_doc.title = title = doc.d$);
			});
		}
	);
});



// ANIMATION


var _Browser_cancelAnimationFrame =
	typeof cancelAnimationFrame !== 'undefined'
		? cancelAnimationFrame
		: function(id) { clearTimeout(id); };

var _Browser_requestAnimationFrame =
	typeof requestAnimationFrame !== 'undefined'
		? requestAnimationFrame
		: function(callback) { return setTimeout(callback, 1000 / 60); };


function _Browser_makeAnimator(model, draw)
{
	draw(model);

	var state = 0;

	function updateIfNeeded()
	{
		state = state === 1
			? 0
			: ( _Browser_requestAnimationFrame(updateIfNeeded), draw(model), 1 );
	}

	return function(nextModel, isSync)
	{
		model = nextModel;

		isSync
			? ( draw(model),
				state === 2 && (state = 1)
				)
			: ( state === 0 && _Browser_requestAnimationFrame(updateIfNeeded),
				state = 2
				);
	};
}



// APPLICATION


function _Browser_application(impl)
{
	var onUrlChange = impl.dI;
	var onUrlRequest = impl.dJ;
	var key = function() { key.a(onUrlChange(_Browser_getUrl())); };

	return _Browser_document({
		bW: function(sendToApp)
		{
			key.a = sendToApp;
			_Browser_window.addEventListener('popstate', key);
			_Browser_window.navigator.userAgent.indexOf('Trident') < 0 || _Browser_window.addEventListener('hashchange', key);

			return F2(function(domNode, event)
			{
				if (!event.ctrlKey && !event.metaKey && !event.shiftKey && event.button < 1 && !domNode.target && !domNode.hasAttribute('download'))
				{
					event.preventDefault();
					var href = domNode.href;
					var curr = _Browser_getUrl();
					var next = $elm$url$Url$fromString(href).a;
					sendToApp(onUrlRequest(
						(next
							&& curr.cI === next.cI
							&& curr.cs === next.cs
							&& curr.cE.a === next.cE.a
						)
							? $elm$browser$Browser$Internal(next)
							: $elm$browser$Browser$External(href)
					));
				}
			});
		},
		dy: function(flags)
		{
			return A3(impl.dy, flags, _Browser_getUrl(), key);
		},
		ea: impl.ea,
		d9: impl.d9,
		dX: impl.dX
	});
}

function _Browser_getUrl()
{
	return $elm$url$Url$fromString(_VirtualDom_doc.location.href).a || _Debug_crash(1);
}

var _Browser_go = F2(function(key, n)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function() {
		n && history.go(n);
		key();
	}));
});

var _Browser_pushUrl = F2(function(key, url)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function() {
		history.pushState({}, '', url);
		key();
	}));
});

var _Browser_replaceUrl = F2(function(key, url)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function() {
		history.replaceState({}, '', url);
		key();
	}));
});



// GLOBAL EVENTS


var _Browser_fakeNode = { addEventListener: function() {}, removeEventListener: function() {} };
var _Browser_doc = typeof document !== 'undefined' ? document : _Browser_fakeNode;
var _Browser_window = typeof window !== 'undefined' ? window : _Browser_fakeNode;

var _Browser_on = F3(function(node, eventName, sendToSelf)
{
	return _Scheduler_spawn(_Scheduler_binding(function(callback)
	{
		function handler(event)	{ _Scheduler_rawSpawn(sendToSelf(event)); }
		node.addEventListener(eventName, handler, _VirtualDom_passiveSupported && { passive: true });
		return function() { node.removeEventListener(eventName, handler); };
	}));
});

var _Browser_decodeEvent = F2(function(decoder, event)
{
	var result = _Json_runHelp(decoder, event);
	return $elm$core$Result$isOk(result) ? $elm$core$Maybe$Just(result.a) : $elm$core$Maybe$Nothing;
});



// PAGE VISIBILITY


function _Browser_visibilityInfo()
{
	return (typeof _VirtualDom_doc.hidden !== 'undefined')
		? { ds: 'hidden', df: 'visibilitychange' }
		:
	(typeof _VirtualDom_doc.mozHidden !== 'undefined')
		? { ds: 'mozHidden', df: 'mozvisibilitychange' }
		:
	(typeof _VirtualDom_doc.msHidden !== 'undefined')
		? { ds: 'msHidden', df: 'msvisibilitychange' }
		:
	(typeof _VirtualDom_doc.webkitHidden !== 'undefined')
		? { ds: 'webkitHidden', df: 'webkitvisibilitychange' }
		: { ds: 'hidden', df: 'visibilitychange' };
}



// ANIMATION FRAMES


function _Browser_rAF()
{
	return _Scheduler_binding(function(callback)
	{
		var id = _Browser_requestAnimationFrame(function() {
			callback(_Scheduler_succeed(Date.now()));
		});

		return function() {
			_Browser_cancelAnimationFrame(id);
		};
	});
}


function _Browser_now()
{
	return _Scheduler_binding(function(callback)
	{
		callback(_Scheduler_succeed(Date.now()));
	});
}



// DOM STUFF


function _Browser_withNode(id, doStuff)
{
	return _Scheduler_binding(function(callback)
	{
		_Browser_requestAnimationFrame(function() {
			var node = document.getElementById(id);
			callback(node
				? _Scheduler_succeed(doStuff(node))
				: _Scheduler_fail($elm$browser$Browser$Dom$NotFound(id))
			);
		});
	});
}


function _Browser_withWindow(doStuff)
{
	return _Scheduler_binding(function(callback)
	{
		_Browser_requestAnimationFrame(function() {
			callback(_Scheduler_succeed(doStuff()));
		});
	});
}


// FOCUS and BLUR


var _Browser_call = F2(function(functionName, id)
{
	return _Browser_withNode(id, function(node) {
		node[functionName]();
		return _Utils_Tuple0;
	});
});



// WINDOW VIEWPORT


function _Browser_getViewport()
{
	return {
		cR: _Browser_getScene(),
		c$: {
			c3: _Browser_window.pageXOffset,
			c4: _Browser_window.pageYOffset,
			c2: _Browser_doc.documentElement.clientWidth,
			cq: _Browser_doc.documentElement.clientHeight
		}
	};
}

function _Browser_getScene()
{
	var body = _Browser_doc.body;
	var elem = _Browser_doc.documentElement;
	return {
		c2: Math.max(body.scrollWidth, body.offsetWidth, elem.scrollWidth, elem.offsetWidth, elem.clientWidth),
		cq: Math.max(body.scrollHeight, body.offsetHeight, elem.scrollHeight, elem.offsetHeight, elem.clientHeight)
	};
}

var _Browser_setViewport = F2(function(x, y)
{
	return _Browser_withWindow(function()
	{
		_Browser_window.scroll(x, y);
		return _Utils_Tuple0;
	});
});



// ELEMENT VIEWPORT


function _Browser_getViewportOf(id)
{
	return _Browser_withNode(id, function(node)
	{
		return {
			cR: {
				c2: node.scrollWidth,
				cq: node.scrollHeight
			},
			c$: {
				c3: node.scrollLeft,
				c4: node.scrollTop,
				c2: node.clientWidth,
				cq: node.clientHeight
			}
		};
	});
}


var _Browser_setViewportOf = F3(function(id, x, y)
{
	return _Browser_withNode(id, function(node)
	{
		node.scrollLeft = x;
		node.scrollTop = y;
		return _Utils_Tuple0;
	});
});



// ELEMENT


function _Browser_getElement(id)
{
	return _Browser_withNode(id, function(node)
	{
		var rect = node.getBoundingClientRect();
		var x = _Browser_window.pageXOffset;
		var y = _Browser_window.pageYOffset;
		return {
			cR: _Browser_getScene(),
			c$: {
				c3: x,
				c4: y,
				c2: _Browser_doc.documentElement.clientWidth,
				cq: _Browser_doc.documentElement.clientHeight
			},
			dn: {
				c3: x + rect.left,
				c4: y + rect.top,
				c2: rect.width,
				cq: rect.height
			}
		};
	});
}



// LOAD and RELOAD


function _Browser_reload(skipCache)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function(callback)
	{
		_VirtualDom_doc.location.reload(skipCache);
	}));
}

function _Browser_load(url)
{
	return A2($elm$core$Task$perform, $elm$core$Basics$never, _Scheduler_binding(function(callback)
	{
		try
		{
			_Browser_window.location = url;
		}
		catch(err)
		{
			// Only Firefox can throw a NS_ERROR_MALFORMED_URI exception here.
			// Other browsers reload the page, so let's be consistent about that.
			_VirtualDom_doc.location.reload(false);
		}
	}));
}



// SEND REQUEST

var _Http_toTask = F3(function(router, toTask, request)
{
	return _Scheduler_binding(function(callback)
	{
		function done(response) {
			callback(toTask(request.a2.a(response)));
		}

		var xhr = new XMLHttpRequest();
		xhr.addEventListener('error', function() { done($elm$http$Http$NetworkError_); });
		xhr.addEventListener('timeout', function() { done($elm$http$Http$Timeout_); });
		xhr.addEventListener('load', function() { done(_Http_toResponse(request.a2.b, xhr)); });
		$elm$core$Maybe$isJust(request.be) && _Http_track(router, xhr, request.be.a);

		try {
			xhr.open(request.a7, request.bh, true);
		} catch (e) {
			return done($elm$http$Http$BadUrl_(request.bh));
		}

		_Http_configureRequest(xhr, request);

		request.aZ.a && xhr.setRequestHeader('Content-Type', request.aZ.a);
		xhr.send(request.aZ.b);

		return function() { xhr.c = true; xhr.abort(); };
	});
});


// CONFIGURE

function _Http_configureRequest(xhr, request)
{
	for (var headers = request.a4; headers.b; headers = headers.b) // WHILE_CONS
	{
		xhr.setRequestHeader(headers.a.a, headers.a.b);
	}
	xhr.timeout = request.bb.a || 0;
	xhr.responseType = request.a2.d;
	xhr.withCredentials = request.c8;
}


// RESPONSES

function _Http_toResponse(toBody, xhr)
{
	return A2(
		200 <= xhr.status && xhr.status < 300 ? $elm$http$Http$GoodStatus_ : $elm$http$Http$BadStatus_,
		_Http_toMetadata(xhr),
		toBody(xhr.response)
	);
}


// METADATA

function _Http_toMetadata(xhr)
{
	return {
		bh: xhr.responseURL,
		bu: xhr.status,
		dW: xhr.statusText,
		a4: _Http_parseHeaders(xhr.getAllResponseHeaders())
	};
}


// HEADERS

function _Http_parseHeaders(rawHeaders)
{
	if (!rawHeaders)
	{
		return $elm$core$Dict$empty;
	}

	var headers = $elm$core$Dict$empty;
	var headerPairs = rawHeaders.split('\r\n');
	for (var i = headerPairs.length; i--; )
	{
		var headerPair = headerPairs[i];
		var index = headerPair.indexOf(': ');
		if (index > 0)
		{
			var key = headerPair.substring(0, index);
			var value = headerPair.substring(index + 2);

			headers = A3($elm$core$Dict$update, key, function(oldValue) {
				return $elm$core$Maybe$Just($elm$core$Maybe$isJust(oldValue)
					? value + ', ' + oldValue.a
					: value
				);
			}, headers);
		}
	}
	return headers;
}


// EXPECT

var _Http_expect = F3(function(type, toBody, toValue)
{
	return {
		$: 0,
		d: type,
		b: toBody,
		a: toValue
	};
});

var _Http_mapExpect = F2(function(func, expect)
{
	return {
		$: 0,
		d: expect.d,
		b: expect.b,
		a: function(x) { return func(expect.a(x)); }
	};
});

function _Http_toDataView(arrayBuffer)
{
	return new DataView(arrayBuffer);
}


// BODY and PARTS

var _Http_emptyBody = { $: 0 };
var _Http_pair = F2(function(a, b) { return { $: 0, a: a, b: b }; });

function _Http_toFormData(parts)
{
	for (var formData = new FormData(); parts.b; parts = parts.b) // WHILE_CONS
	{
		var part = parts.a;
		formData.append(part.a, part.b);
	}
	return formData;
}

var _Http_bytesToBlob = F2(function(mime, bytes)
{
	return new Blob([bytes], { type: mime });
});


// PROGRESS

function _Http_track(router, xhr, tracker)
{
	// TODO check out lengthComputable on loadstart event

	xhr.upload.addEventListener('progress', function(event) {
		if (xhr.c) { return; }
		_Scheduler_rawSpawn(A2($elm$core$Platform$sendToSelf, router, _Utils_Tuple2(tracker, $elm$http$Http$Sending({
			dS: event.loaded,
			cU: event.total
		}))));
	});
	xhr.addEventListener('progress', function(event) {
		if (xhr.c) { return; }
		_Scheduler_rawSpawn(A2($elm$core$Platform$sendToSelf, router, _Utils_Tuple2(tracker, $elm$http$Http$Receiving({
			dO: event.loaded,
			cU: event.lengthComputable ? $elm$core$Maybe$Just(event.total) : $elm$core$Maybe$Nothing
		}))));
	});
}


function _Time_now(millisToPosix)
{
	return _Scheduler_binding(function(callback)
	{
		callback(_Scheduler_succeed(millisToPosix(Date.now())));
	});
}

var _Time_setInterval = F2(function(interval, task)
{
	return _Scheduler_binding(function(callback)
	{
		var id = setInterval(function() { _Scheduler_rawSpawn(task); }, interval);
		return function() { clearInterval(id); };
	});
});

function _Time_here()
{
	return _Scheduler_binding(function(callback)
	{
		callback(_Scheduler_succeed(
			A2($elm$time$Time$customZone, -(new Date().getTimezoneOffset()), _List_Nil)
		));
	});
}


function _Time_getZoneName()
{
	return _Scheduler_binding(function(callback)
	{
		try
		{
			var name = $elm$time$Time$Name(Intl.DateTimeFormat().resolvedOptions().timeZone);
		}
		catch (e)
		{
			var name = $elm$time$Time$Offset(new Date().getTimezoneOffset());
		}
		callback(_Scheduler_succeed(name));
	});
}



var _Bitwise_and = F2(function(a, b)
{
	return a & b;
});

var _Bitwise_or = F2(function(a, b)
{
	return a | b;
});

var _Bitwise_xor = F2(function(a, b)
{
	return a ^ b;
});

function _Bitwise_complement(a)
{
	return ~a;
};

var _Bitwise_shiftLeftBy = F2(function(offset, a)
{
	return a << offset;
});

var _Bitwise_shiftRightBy = F2(function(offset, a)
{
	return a >> offset;
});

var _Bitwise_shiftRightZfBy = F2(function(offset, a)
{
	return a >>> offset;
});



// DECODER

var _File_decoder = _Json_decodePrim(function(value) {
	// NOTE: checks if `File` exists in case this is run on node
	return (typeof File !== 'undefined' && value instanceof File)
		? $elm$core$Result$Ok(value)
		: _Json_expecting('a FILE', value);
});


// METADATA

function _File_name(file) { return file.name; }
function _File_mime(file) { return file.type; }
function _File_size(file) { return file.size; }

function _File_lastModified(file)
{
	return $elm$time$Time$millisToPosix(file.lastModified);
}


// DOWNLOAD

var _File_downloadNode;

function _File_getDownloadNode()
{
	return _File_downloadNode || (_File_downloadNode = document.createElement('a'));
}

var _File_download = F3(function(name, mime, content)
{
	return _Scheduler_binding(function(callback)
	{
		var blob = new Blob([content], {type: mime});

		// for IE10+
		if (navigator.msSaveOrOpenBlob)
		{
			navigator.msSaveOrOpenBlob(blob, name);
			return;
		}

		// for HTML5
		var node = _File_getDownloadNode();
		var objectUrl = URL.createObjectURL(blob);
		node.href = objectUrl;
		node.download = name;
		_File_click(node);
		URL.revokeObjectURL(objectUrl);
	});
});

function _File_downloadUrl(href)
{
	return _Scheduler_binding(function(callback)
	{
		var node = _File_getDownloadNode();
		node.href = href;
		node.download = '';
		node.origin === location.origin || (node.target = '_blank');
		_File_click(node);
	});
}


// IE COMPATIBILITY

function _File_makeBytesSafeForInternetExplorer(bytes)
{
	// only needed by IE10 and IE11 to fix https://github.com/elm/file/issues/10
	// all other browsers can just run `new Blob([bytes])` directly with no problem
	//
	return new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
}

function _File_click(node)
{
	// only needed by IE10 and IE11 to fix https://github.com/elm/file/issues/11
	// all other browsers have MouseEvent and do not need this conditional stuff
	//
	if (typeof MouseEvent === 'function')
	{
		node.dispatchEvent(new MouseEvent('click'));
	}
	else
	{
		var event = document.createEvent('MouseEvents');
		event.initMouseEvent('click', true, true, window, 0, 0, 0, 0, 0, false, false, false, false, 0, null);
		document.body.appendChild(node);
		node.dispatchEvent(event);
		document.body.removeChild(node);
	}
}


// UPLOAD

var _File_node;

function _File_uploadOne(mimes)
{
	return _Scheduler_binding(function(callback)
	{
		_File_node = document.createElement('input');
		_File_node.type = 'file';
		_File_node.accept = A2($elm$core$String$join, ',', mimes);
		_File_node.addEventListener('change', function(event)
		{
			callback(_Scheduler_succeed(event.target.files[0]));
		});
		_File_click(_File_node);
	});
}

function _File_uploadOneOrMore(mimes)
{
	return _Scheduler_binding(function(callback)
	{
		_File_node = document.createElement('input');
		_File_node.type = 'file';
		_File_node.multiple = true;
		_File_node.accept = A2($elm$core$String$join, ',', mimes);
		_File_node.addEventListener('change', function(event)
		{
			var elmFiles = _List_fromArray(event.target.files);
			callback(_Scheduler_succeed(_Utils_Tuple2(elmFiles.a, elmFiles.b)));
		});
		_File_click(_File_node);
	});
}


// CONTENT

function _File_toString(blob)
{
	return _Scheduler_binding(function(callback)
	{
		var reader = new FileReader();
		reader.addEventListener('loadend', function() {
			callback(_Scheduler_succeed(reader.result));
		});
		reader.readAsText(blob);
		return function() { reader.abort(); };
	});
}

function _File_toBytes(blob)
{
	return _Scheduler_binding(function(callback)
	{
		var reader = new FileReader();
		reader.addEventListener('loadend', function() {
			callback(_Scheduler_succeed(new DataView(reader.result)));
		});
		reader.readAsArrayBuffer(blob);
		return function() { reader.abort(); };
	});
}

function _File_toUrl(blob)
{
	return _Scheduler_binding(function(callback)
	{
		var reader = new FileReader();
		reader.addEventListener('loadend', function() {
			callback(_Scheduler_succeed(reader.result));
		});
		reader.readAsDataURL(blob);
		return function() { reader.abort(); };
	});
}

var $elm$core$List$cons = _List_cons;
var $elm$core$Elm$JsArray$foldr = _JsArray_foldr;
var $elm$core$Array$foldr = F3(
	function (func, baseCase, _v0) {
		var tree = _v0.c;
		var tail = _v0.d;
		var helper = F2(
			function (node, acc) {
				if (!node.$) {
					var subTree = node.a;
					return A3($elm$core$Elm$JsArray$foldr, helper, acc, subTree);
				} else {
					var values = node.a;
					return A3($elm$core$Elm$JsArray$foldr, func, acc, values);
				}
			});
		return A3(
			$elm$core$Elm$JsArray$foldr,
			helper,
			A3($elm$core$Elm$JsArray$foldr, func, baseCase, tail),
			tree);
	});
var $elm$core$Array$toList = function (array) {
	return A3($elm$core$Array$foldr, $elm$core$List$cons, _List_Nil, array);
};
var $elm$core$Dict$foldr = F3(
	function (func, acc, t) {
		foldr:
		while (true) {
			if (t.$ === -2) {
				return acc;
			} else {
				var key = t.b;
				var value = t.c;
				var left = t.d;
				var right = t.e;
				var $temp$func = func,
					$temp$acc = A3(
					func,
					key,
					value,
					A3($elm$core$Dict$foldr, func, acc, right)),
					$temp$t = left;
				func = $temp$func;
				acc = $temp$acc;
				t = $temp$t;
				continue foldr;
			}
		}
	});
var $elm$core$Dict$toList = function (dict) {
	return A3(
		$elm$core$Dict$foldr,
		F3(
			function (key, value, list) {
				return A2(
					$elm$core$List$cons,
					_Utils_Tuple2(key, value),
					list);
			}),
		_List_Nil,
		dict);
};
var $elm$core$Dict$keys = function (dict) {
	return A3(
		$elm$core$Dict$foldr,
		F3(
			function (key, value, keyList) {
				return A2($elm$core$List$cons, key, keyList);
			}),
		_List_Nil,
		dict);
};
var $elm$core$Set$toList = function (_v0) {
	var dict = _v0;
	return $elm$core$Dict$keys(dict);
};
var $elm$core$Basics$EQ = 1;
var $elm$core$Basics$GT = 2;
var $elm$core$Basics$LT = 0;
var $author$project$Main$GeolocationDenied = {$: 36};
var $author$project$Main$GotExifCoords = F4(
	function (a, b, c, d) {
		return {$: 41, a: a, b: b, c: c, d: d};
	});
var $author$project$Main$GotGpsCoords = F2(
	function (a, b) {
		return {$: 35, a: a, b: b};
	});
var $author$project$Main$GotOAuthToken = function (a) {
	return {$: 0, a: a};
};
var $elm$core$Maybe$Just = function (a) {
	return {$: 0, a: a};
};
var $elm$core$Maybe$Nothing = {$: 1};
var $elm$core$Result$Err = function (a) {
	return {$: 1, a: a};
};
var $elm$json$Json$Decode$Failure = F2(
	function (a, b) {
		return {$: 3, a: a, b: b};
	});
var $elm$json$Json$Decode$Field = F2(
	function (a, b) {
		return {$: 0, a: a, b: b};
	});
var $elm$json$Json$Decode$Index = F2(
	function (a, b) {
		return {$: 1, a: a, b: b};
	});
var $elm$core$Result$Ok = function (a) {
	return {$: 0, a: a};
};
var $elm$json$Json$Decode$OneOf = function (a) {
	return {$: 2, a: a};
};
var $elm$core$Basics$False = 1;
var $elm$core$Basics$add = _Basics_add;
var $elm$core$String$all = _String_all;
var $elm$core$Basics$and = _Basics_and;
var $elm$core$Basics$append = _Utils_append;
var $elm$json$Json$Encode$encode = _Json_encode;
var $elm$core$String$fromInt = _String_fromNumber;
var $elm$core$String$join = F2(
	function (sep, chunks) {
		return A2(
			_String_join,
			sep,
			_List_toArray(chunks));
	});
var $elm$core$String$split = F2(
	function (sep, string) {
		return _List_fromArray(
			A2(_String_split, sep, string));
	});
var $elm$json$Json$Decode$indent = function (str) {
	return A2(
		$elm$core$String$join,
		'\n    ',
		A2($elm$core$String$split, '\n', str));
};
var $elm$core$List$foldl = F3(
	function (func, acc, list) {
		foldl:
		while (true) {
			if (!list.b) {
				return acc;
			} else {
				var x = list.a;
				var xs = list.b;
				var $temp$func = func,
					$temp$acc = A2(func, x, acc),
					$temp$list = xs;
				func = $temp$func;
				acc = $temp$acc;
				list = $temp$list;
				continue foldl;
			}
		}
	});
var $elm$core$List$length = function (xs) {
	return A3(
		$elm$core$List$foldl,
		F2(
			function (_v0, i) {
				return i + 1;
			}),
		0,
		xs);
};
var $elm$core$List$map2 = _List_map2;
var $elm$core$Basics$le = _Utils_le;
var $elm$core$Basics$sub = _Basics_sub;
var $elm$core$List$rangeHelp = F3(
	function (lo, hi, list) {
		rangeHelp:
		while (true) {
			if (_Utils_cmp(lo, hi) < 1) {
				var $temp$lo = lo,
					$temp$hi = hi - 1,
					$temp$list = A2($elm$core$List$cons, hi, list);
				lo = $temp$lo;
				hi = $temp$hi;
				list = $temp$list;
				continue rangeHelp;
			} else {
				return list;
			}
		}
	});
var $elm$core$List$range = F2(
	function (lo, hi) {
		return A3($elm$core$List$rangeHelp, lo, hi, _List_Nil);
	});
var $elm$core$List$indexedMap = F2(
	function (f, xs) {
		return A3(
			$elm$core$List$map2,
			f,
			A2(
				$elm$core$List$range,
				0,
				$elm$core$List$length(xs) - 1),
			xs);
	});
var $elm$core$Char$toCode = _Char_toCode;
var $elm$core$Char$isLower = function (_char) {
	var code = $elm$core$Char$toCode(_char);
	return (97 <= code) && (code <= 122);
};
var $elm$core$Char$isUpper = function (_char) {
	var code = $elm$core$Char$toCode(_char);
	return (code <= 90) && (65 <= code);
};
var $elm$core$Basics$or = _Basics_or;
var $elm$core$Char$isAlpha = function (_char) {
	return $elm$core$Char$isLower(_char) || $elm$core$Char$isUpper(_char);
};
var $elm$core$Char$isDigit = function (_char) {
	var code = $elm$core$Char$toCode(_char);
	return (code <= 57) && (48 <= code);
};
var $elm$core$Char$isAlphaNum = function (_char) {
	return $elm$core$Char$isLower(_char) || ($elm$core$Char$isUpper(_char) || $elm$core$Char$isDigit(_char));
};
var $elm$core$List$reverse = function (list) {
	return A3($elm$core$List$foldl, $elm$core$List$cons, _List_Nil, list);
};
var $elm$core$String$uncons = _String_uncons;
var $elm$json$Json$Decode$errorOneOf = F2(
	function (i, error) {
		return '\n\n(' + ($elm$core$String$fromInt(i + 1) + (') ' + $elm$json$Json$Decode$indent(
			$elm$json$Json$Decode$errorToString(error))));
	});
var $elm$json$Json$Decode$errorToString = function (error) {
	return A2($elm$json$Json$Decode$errorToStringHelp, error, _List_Nil);
};
var $elm$json$Json$Decode$errorToStringHelp = F2(
	function (error, context) {
		errorToStringHelp:
		while (true) {
			switch (error.$) {
				case 0:
					var f = error.a;
					var err = error.b;
					var isSimple = function () {
						var _v1 = $elm$core$String$uncons(f);
						if (_v1.$ === 1) {
							return false;
						} else {
							var _v2 = _v1.a;
							var _char = _v2.a;
							var rest = _v2.b;
							return $elm$core$Char$isAlpha(_char) && A2($elm$core$String$all, $elm$core$Char$isAlphaNum, rest);
						}
					}();
					var fieldName = isSimple ? ('.' + f) : ('[\'' + (f + '\']'));
					var $temp$error = err,
						$temp$context = A2($elm$core$List$cons, fieldName, context);
					error = $temp$error;
					context = $temp$context;
					continue errorToStringHelp;
				case 1:
					var i = error.a;
					var err = error.b;
					var indexName = '[' + ($elm$core$String$fromInt(i) + ']');
					var $temp$error = err,
						$temp$context = A2($elm$core$List$cons, indexName, context);
					error = $temp$error;
					context = $temp$context;
					continue errorToStringHelp;
				case 2:
					var errors = error.a;
					if (!errors.b) {
						return 'Ran into a Json.Decode.oneOf with no possibilities' + function () {
							if (!context.b) {
								return '!';
							} else {
								return ' at json' + A2(
									$elm$core$String$join,
									'',
									$elm$core$List$reverse(context));
							}
						}();
					} else {
						if (!errors.b.b) {
							var err = errors.a;
							var $temp$error = err,
								$temp$context = context;
							error = $temp$error;
							context = $temp$context;
							continue errorToStringHelp;
						} else {
							var starter = function () {
								if (!context.b) {
									return 'Json.Decode.oneOf';
								} else {
									return 'The Json.Decode.oneOf at json' + A2(
										$elm$core$String$join,
										'',
										$elm$core$List$reverse(context));
								}
							}();
							var introduction = starter + (' failed in the following ' + ($elm$core$String$fromInt(
								$elm$core$List$length(errors)) + ' ways:'));
							return A2(
								$elm$core$String$join,
								'\n\n',
								A2(
									$elm$core$List$cons,
									introduction,
									A2($elm$core$List$indexedMap, $elm$json$Json$Decode$errorOneOf, errors)));
						}
					}
				default:
					var msg = error.a;
					var json = error.b;
					var introduction = function () {
						if (!context.b) {
							return 'Problem with the given value:\n\n';
						} else {
							return 'Problem with the value at json' + (A2(
								$elm$core$String$join,
								'',
								$elm$core$List$reverse(context)) + ':\n\n    ');
						}
					}();
					return introduction + ($elm$json$Json$Decode$indent(
						A2($elm$json$Json$Encode$encode, 4, json)) + ('\n\n' + msg));
			}
		}
	});
var $elm$core$Array$branchFactor = 32;
var $elm$core$Array$Array_elm_builtin = F4(
	function (a, b, c, d) {
		return {$: 0, a: a, b: b, c: c, d: d};
	});
var $elm$core$Elm$JsArray$empty = _JsArray_empty;
var $elm$core$Basics$ceiling = _Basics_ceiling;
var $elm$core$Basics$fdiv = _Basics_fdiv;
var $elm$core$Basics$logBase = F2(
	function (base, number) {
		return _Basics_log(number) / _Basics_log(base);
	});
var $elm$core$Basics$toFloat = _Basics_toFloat;
var $elm$core$Array$shiftStep = $elm$core$Basics$ceiling(
	A2($elm$core$Basics$logBase, 2, $elm$core$Array$branchFactor));
var $elm$core$Array$empty = A4($elm$core$Array$Array_elm_builtin, 0, $elm$core$Array$shiftStep, $elm$core$Elm$JsArray$empty, $elm$core$Elm$JsArray$empty);
var $elm$core$Elm$JsArray$initialize = _JsArray_initialize;
var $elm$core$Array$Leaf = function (a) {
	return {$: 1, a: a};
};
var $elm$core$Basics$apL = F2(
	function (f, x) {
		return f(x);
	});
var $elm$core$Basics$apR = F2(
	function (x, f) {
		return f(x);
	});
var $elm$core$Basics$eq = _Utils_equal;
var $elm$core$Basics$floor = _Basics_floor;
var $elm$core$Elm$JsArray$length = _JsArray_length;
var $elm$core$Basics$gt = _Utils_gt;
var $elm$core$Basics$max = F2(
	function (x, y) {
		return (_Utils_cmp(x, y) > 0) ? x : y;
	});
var $elm$core$Basics$mul = _Basics_mul;
var $elm$core$Array$SubTree = function (a) {
	return {$: 0, a: a};
};
var $elm$core$Elm$JsArray$initializeFromList = _JsArray_initializeFromList;
var $elm$core$Array$compressNodes = F2(
	function (nodes, acc) {
		compressNodes:
		while (true) {
			var _v0 = A2($elm$core$Elm$JsArray$initializeFromList, $elm$core$Array$branchFactor, nodes);
			var node = _v0.a;
			var remainingNodes = _v0.b;
			var newAcc = A2(
				$elm$core$List$cons,
				$elm$core$Array$SubTree(node),
				acc);
			if (!remainingNodes.b) {
				return $elm$core$List$reverse(newAcc);
			} else {
				var $temp$nodes = remainingNodes,
					$temp$acc = newAcc;
				nodes = $temp$nodes;
				acc = $temp$acc;
				continue compressNodes;
			}
		}
	});
var $elm$core$Tuple$first = function (_v0) {
	var x = _v0.a;
	return x;
};
var $elm$core$Array$treeFromBuilder = F2(
	function (nodeList, nodeListSize) {
		treeFromBuilder:
		while (true) {
			var newNodeSize = $elm$core$Basics$ceiling(nodeListSize / $elm$core$Array$branchFactor);
			if (newNodeSize === 1) {
				return A2($elm$core$Elm$JsArray$initializeFromList, $elm$core$Array$branchFactor, nodeList).a;
			} else {
				var $temp$nodeList = A2($elm$core$Array$compressNodes, nodeList, _List_Nil),
					$temp$nodeListSize = newNodeSize;
				nodeList = $temp$nodeList;
				nodeListSize = $temp$nodeListSize;
				continue treeFromBuilder;
			}
		}
	});
var $elm$core$Array$builderToArray = F2(
	function (reverseNodeList, builder) {
		if (!builder.y) {
			return A4(
				$elm$core$Array$Array_elm_builtin,
				$elm$core$Elm$JsArray$length(builder.G),
				$elm$core$Array$shiftStep,
				$elm$core$Elm$JsArray$empty,
				builder.G);
		} else {
			var treeLen = builder.y * $elm$core$Array$branchFactor;
			var depth = $elm$core$Basics$floor(
				A2($elm$core$Basics$logBase, $elm$core$Array$branchFactor, treeLen - 1));
			var correctNodeList = reverseNodeList ? $elm$core$List$reverse(builder.H) : builder.H;
			var tree = A2($elm$core$Array$treeFromBuilder, correctNodeList, builder.y);
			return A4(
				$elm$core$Array$Array_elm_builtin,
				$elm$core$Elm$JsArray$length(builder.G) + treeLen,
				A2($elm$core$Basics$max, 5, depth * $elm$core$Array$shiftStep),
				tree,
				builder.G);
		}
	});
var $elm$core$Basics$idiv = _Basics_idiv;
var $elm$core$Basics$lt = _Utils_lt;
var $elm$core$Array$initializeHelp = F5(
	function (fn, fromIndex, len, nodeList, tail) {
		initializeHelp:
		while (true) {
			if (fromIndex < 0) {
				return A2(
					$elm$core$Array$builderToArray,
					false,
					{H: nodeList, y: (len / $elm$core$Array$branchFactor) | 0, G: tail});
			} else {
				var leaf = $elm$core$Array$Leaf(
					A3($elm$core$Elm$JsArray$initialize, $elm$core$Array$branchFactor, fromIndex, fn));
				var $temp$fn = fn,
					$temp$fromIndex = fromIndex - $elm$core$Array$branchFactor,
					$temp$len = len,
					$temp$nodeList = A2($elm$core$List$cons, leaf, nodeList),
					$temp$tail = tail;
				fn = $temp$fn;
				fromIndex = $temp$fromIndex;
				len = $temp$len;
				nodeList = $temp$nodeList;
				tail = $temp$tail;
				continue initializeHelp;
			}
		}
	});
var $elm$core$Basics$remainderBy = _Basics_remainderBy;
var $elm$core$Array$initialize = F2(
	function (len, fn) {
		if (len <= 0) {
			return $elm$core$Array$empty;
		} else {
			var tailLen = len % $elm$core$Array$branchFactor;
			var tail = A3($elm$core$Elm$JsArray$initialize, tailLen, len - tailLen, fn);
			var initialFromIndex = (len - tailLen) - $elm$core$Array$branchFactor;
			return A5($elm$core$Array$initializeHelp, fn, initialFromIndex, len, _List_Nil, tail);
		}
	});
var $elm$core$Basics$True = 0;
var $elm$core$Result$isOk = function (result) {
	if (!result.$) {
		return true;
	} else {
		return false;
	}
};
var $elm$core$Platform$Sub$batch = _Platform_batch;
var $elm$json$Json$Decode$map = _Json_map1;
var $elm$json$Json$Decode$map2 = _Json_map2;
var $elm$json$Json$Decode$succeed = _Json_succeed;
var $elm$virtual_dom$VirtualDom$toHandlerInt = function (handler) {
	switch (handler.$) {
		case 0:
			return 0;
		case 1:
			return 1;
		case 2:
			return 2;
		default:
			return 3;
	}
};
var $elm$browser$Browser$External = function (a) {
	return {$: 1, a: a};
};
var $elm$browser$Browser$Internal = function (a) {
	return {$: 0, a: a};
};
var $elm$core$Basics$identity = function (x) {
	return x;
};
var $elm$browser$Browser$Dom$NotFound = $elm$core$Basics$identity;
var $elm$url$Url$Http = 0;
var $elm$url$Url$Https = 1;
var $elm$url$Url$Url = F6(
	function (protocol, host, port_, path, query, fragment) {
		return {cn: fragment, cs: host, cC: path, cE: port_, cI: protocol, cJ: query};
	});
var $elm$core$String$contains = _String_contains;
var $elm$core$String$length = _String_length;
var $elm$core$String$slice = _String_slice;
var $elm$core$String$dropLeft = F2(
	function (n, string) {
		return (n < 1) ? string : A3(
			$elm$core$String$slice,
			n,
			$elm$core$String$length(string),
			string);
	});
var $elm$core$String$indexes = _String_indexes;
var $elm$core$String$isEmpty = function (string) {
	return string === '';
};
var $elm$core$String$left = F2(
	function (n, string) {
		return (n < 1) ? '' : A3($elm$core$String$slice, 0, n, string);
	});
var $elm$core$String$toInt = _String_toInt;
var $elm$url$Url$chompBeforePath = F5(
	function (protocol, path, params, frag, str) {
		if ($elm$core$String$isEmpty(str) || A2($elm$core$String$contains, '@', str)) {
			return $elm$core$Maybe$Nothing;
		} else {
			var _v0 = A2($elm$core$String$indexes, ':', str);
			if (!_v0.b) {
				return $elm$core$Maybe$Just(
					A6($elm$url$Url$Url, protocol, str, $elm$core$Maybe$Nothing, path, params, frag));
			} else {
				if (!_v0.b.b) {
					var i = _v0.a;
					var _v1 = $elm$core$String$toInt(
						A2($elm$core$String$dropLeft, i + 1, str));
					if (_v1.$ === 1) {
						return $elm$core$Maybe$Nothing;
					} else {
						var port_ = _v1;
						return $elm$core$Maybe$Just(
							A6(
								$elm$url$Url$Url,
								protocol,
								A2($elm$core$String$left, i, str),
								port_,
								path,
								params,
								frag));
					}
				} else {
					return $elm$core$Maybe$Nothing;
				}
			}
		}
	});
var $elm$url$Url$chompBeforeQuery = F4(
	function (protocol, params, frag, str) {
		if ($elm$core$String$isEmpty(str)) {
			return $elm$core$Maybe$Nothing;
		} else {
			var _v0 = A2($elm$core$String$indexes, '/', str);
			if (!_v0.b) {
				return A5($elm$url$Url$chompBeforePath, protocol, '/', params, frag, str);
			} else {
				var i = _v0.a;
				return A5(
					$elm$url$Url$chompBeforePath,
					protocol,
					A2($elm$core$String$dropLeft, i, str),
					params,
					frag,
					A2($elm$core$String$left, i, str));
			}
		}
	});
var $elm$url$Url$chompBeforeFragment = F3(
	function (protocol, frag, str) {
		if ($elm$core$String$isEmpty(str)) {
			return $elm$core$Maybe$Nothing;
		} else {
			var _v0 = A2($elm$core$String$indexes, '?', str);
			if (!_v0.b) {
				return A4($elm$url$Url$chompBeforeQuery, protocol, $elm$core$Maybe$Nothing, frag, str);
			} else {
				var i = _v0.a;
				return A4(
					$elm$url$Url$chompBeforeQuery,
					protocol,
					$elm$core$Maybe$Just(
						A2($elm$core$String$dropLeft, i + 1, str)),
					frag,
					A2($elm$core$String$left, i, str));
			}
		}
	});
var $elm$url$Url$chompAfterProtocol = F2(
	function (protocol, str) {
		if ($elm$core$String$isEmpty(str)) {
			return $elm$core$Maybe$Nothing;
		} else {
			var _v0 = A2($elm$core$String$indexes, '#', str);
			if (!_v0.b) {
				return A3($elm$url$Url$chompBeforeFragment, protocol, $elm$core$Maybe$Nothing, str);
			} else {
				var i = _v0.a;
				return A3(
					$elm$url$Url$chompBeforeFragment,
					protocol,
					$elm$core$Maybe$Just(
						A2($elm$core$String$dropLeft, i + 1, str)),
					A2($elm$core$String$left, i, str));
			}
		}
	});
var $elm$core$String$startsWith = _String_startsWith;
var $elm$url$Url$fromString = function (str) {
	return A2($elm$core$String$startsWith, 'http://', str) ? A2(
		$elm$url$Url$chompAfterProtocol,
		0,
		A2($elm$core$String$dropLeft, 7, str)) : (A2($elm$core$String$startsWith, 'https://', str) ? A2(
		$elm$url$Url$chompAfterProtocol,
		1,
		A2($elm$core$String$dropLeft, 8, str)) : $elm$core$Maybe$Nothing);
};
var $elm$core$Basics$never = function (_v0) {
	never:
	while (true) {
		var nvr = _v0;
		var $temp$_v0 = nvr;
		_v0 = $temp$_v0;
		continue never;
	}
};
var $elm$core$Task$Perform = $elm$core$Basics$identity;
var $elm$core$Task$succeed = _Scheduler_succeed;
var $elm$core$Task$init = $elm$core$Task$succeed(0);
var $elm$core$List$foldrHelper = F4(
	function (fn, acc, ctr, ls) {
		if (!ls.b) {
			return acc;
		} else {
			var a = ls.a;
			var r1 = ls.b;
			if (!r1.b) {
				return A2(fn, a, acc);
			} else {
				var b = r1.a;
				var r2 = r1.b;
				if (!r2.b) {
					return A2(
						fn,
						a,
						A2(fn, b, acc));
				} else {
					var c = r2.a;
					var r3 = r2.b;
					if (!r3.b) {
						return A2(
							fn,
							a,
							A2(
								fn,
								b,
								A2(fn, c, acc)));
					} else {
						var d = r3.a;
						var r4 = r3.b;
						var res = (ctr > 500) ? A3(
							$elm$core$List$foldl,
							fn,
							acc,
							$elm$core$List$reverse(r4)) : A4($elm$core$List$foldrHelper, fn, acc, ctr + 1, r4);
						return A2(
							fn,
							a,
							A2(
								fn,
								b,
								A2(
									fn,
									c,
									A2(fn, d, res))));
					}
				}
			}
		}
	});
var $elm$core$List$foldr = F3(
	function (fn, acc, ls) {
		return A4($elm$core$List$foldrHelper, fn, acc, 0, ls);
	});
var $elm$core$List$map = F2(
	function (f, xs) {
		return A3(
			$elm$core$List$foldr,
			F2(
				function (x, acc) {
					return A2(
						$elm$core$List$cons,
						f(x),
						acc);
				}),
			_List_Nil,
			xs);
	});
var $elm$core$Task$andThen = _Scheduler_andThen;
var $elm$core$Task$map = F2(
	function (func, taskA) {
		return A2(
			$elm$core$Task$andThen,
			function (a) {
				return $elm$core$Task$succeed(
					func(a));
			},
			taskA);
	});
var $elm$core$Task$map2 = F3(
	function (func, taskA, taskB) {
		return A2(
			$elm$core$Task$andThen,
			function (a) {
				return A2(
					$elm$core$Task$andThen,
					function (b) {
						return $elm$core$Task$succeed(
							A2(func, a, b));
					},
					taskB);
			},
			taskA);
	});
var $elm$core$Task$sequence = function (tasks) {
	return A3(
		$elm$core$List$foldr,
		$elm$core$Task$map2($elm$core$List$cons),
		$elm$core$Task$succeed(_List_Nil),
		tasks);
};
var $elm$core$Platform$sendToApp = _Platform_sendToApp;
var $elm$core$Task$spawnCmd = F2(
	function (router, _v0) {
		var task = _v0;
		return _Scheduler_spawn(
			A2(
				$elm$core$Task$andThen,
				$elm$core$Platform$sendToApp(router),
				task));
	});
var $elm$core$Task$onEffects = F3(
	function (router, commands, state) {
		return A2(
			$elm$core$Task$map,
			function (_v0) {
				return 0;
			},
			$elm$core$Task$sequence(
				A2(
					$elm$core$List$map,
					$elm$core$Task$spawnCmd(router),
					commands)));
	});
var $elm$core$Task$onSelfMsg = F3(
	function (_v0, _v1, _v2) {
		return $elm$core$Task$succeed(0);
	});
var $elm$core$Task$cmdMap = F2(
	function (tagger, _v0) {
		var task = _v0;
		return A2($elm$core$Task$map, tagger, task);
	});
_Platform_effectManagers['Task'] = _Platform_createManager($elm$core$Task$init, $elm$core$Task$onEffects, $elm$core$Task$onSelfMsg, $elm$core$Task$cmdMap);
var $elm$core$Task$command = _Platform_leaf('Task');
var $elm$core$Task$perform = F2(
	function (toMessage, task) {
		return $elm$core$Task$command(
			A2($elm$core$Task$map, toMessage, task));
	});
var $elm$browser$Browser$element = _Browser_element;
var $elm$json$Json$Decode$andThen = _Json_andThen;
var $elm$json$Json$Decode$bool = _Json_decodeBool;
var $elm$json$Json$Decode$field = _Json_decodeField;
var $elm$json$Json$Decode$float = _Json_decodeFloat;
var $elm$json$Json$Decode$string = _Json_decodeString;
var $author$project$Main$gotExifResult = _Platform_incomingPort(
	'gotExifResult',
	A2(
		$elm$json$Json$Decode$andThen,
		function (lon) {
			return A2(
				$elm$json$Json$Decode$andThen,
				function (lat) {
					return A2(
						$elm$json$Json$Decode$andThen,
						function (id) {
							return A2(
								$elm$json$Json$Decode$andThen,
								function (hasGps) {
									return A2(
										$elm$json$Json$Decode$andThen,
										function (debug) {
											return $elm$json$Json$Decode$succeed(
												{ch: debug, cp: hasGps, E: id, M: lat, P: lon});
										},
										A2($elm$json$Json$Decode$field, 'debug', $elm$json$Json$Decode$string));
								},
								A2($elm$json$Json$Decode$field, 'hasGps', $elm$json$Json$Decode$bool));
						},
						A2($elm$json$Json$Decode$field, 'id', $elm$json$Json$Decode$string));
				},
				A2($elm$json$Json$Decode$field, 'lat', $elm$json$Json$Decode$float));
		},
		A2($elm$json$Json$Decode$field, 'lon', $elm$json$Json$Decode$float)));
var $author$project$Main$gotGpsCoords = _Platform_incomingPort(
	'gotGpsCoords',
	A2(
		$elm$json$Json$Decode$andThen,
		function (lon) {
			return A2(
				$elm$json$Json$Decode$andThen,
				function (lat) {
					return A2(
						$elm$json$Json$Decode$andThen,
						function (denied) {
							return $elm$json$Json$Decode$succeed(
								{ci: denied, M: lat, P: lon});
						},
						A2($elm$json$Json$Decode$field, 'denied', $elm$json$Json$Decode$bool));
				},
				A2($elm$json$Json$Decode$field, 'lat', $elm$json$Json$Decode$float));
		},
		A2($elm$json$Json$Decode$field, 'lon', $elm$json$Json$Decode$float)));
var $author$project$Main$gotNewToken = _Platform_incomingPort('gotNewToken', $elm$json$Json$Decode$string);
var $author$project$Main$AuthModel = function (a) {
	return {$: 1, a: a};
};
var $author$project$Main$FreshGuest = 0;
var $author$project$Main$GuestModel = function (a) {
	return {$: 0, a: a};
};
var $elm$core$Maybe$andThen = F2(
	function (callback, maybeValue) {
		if (!maybeValue.$) {
			var value = maybeValue.a;
			return callback(value);
		} else {
			return $elm$core$Maybe$Nothing;
		}
	});
var $elm$json$Json$Decode$decodeValue = _Json_run;
var $author$project$Main$EntriesFetched = function (a) {
	return {$: 23, a: a};
};
var $elm$http$Http$BadStatus_ = F2(
	function (a, b) {
		return {$: 3, a: a, b: b};
	});
var $elm$http$Http$BadUrl_ = function (a) {
	return {$: 0, a: a};
};
var $elm$http$Http$GoodStatus_ = F2(
	function (a, b) {
		return {$: 4, a: a, b: b};
	});
var $elm$http$Http$NetworkError_ = {$: 2};
var $elm$http$Http$Receiving = function (a) {
	return {$: 1, a: a};
};
var $elm$http$Http$Sending = function (a) {
	return {$: 0, a: a};
};
var $elm$http$Http$Timeout_ = {$: 1};
var $elm$core$Dict$RBEmpty_elm_builtin = {$: -2};
var $elm$core$Dict$empty = $elm$core$Dict$RBEmpty_elm_builtin;
var $elm$core$Maybe$isJust = function (maybe) {
	if (!maybe.$) {
		return true;
	} else {
		return false;
	}
};
var $elm$core$Platform$sendToSelf = _Platform_sendToSelf;
var $elm$core$Basics$compare = _Utils_compare;
var $elm$core$Dict$get = F2(
	function (targetKey, dict) {
		get:
		while (true) {
			if (dict.$ === -2) {
				return $elm$core$Maybe$Nothing;
			} else {
				var key = dict.b;
				var value = dict.c;
				var left = dict.d;
				var right = dict.e;
				var _v1 = A2($elm$core$Basics$compare, targetKey, key);
				switch (_v1) {
					case 0:
						var $temp$targetKey = targetKey,
							$temp$dict = left;
						targetKey = $temp$targetKey;
						dict = $temp$dict;
						continue get;
					case 1:
						return $elm$core$Maybe$Just(value);
					default:
						var $temp$targetKey = targetKey,
							$temp$dict = right;
						targetKey = $temp$targetKey;
						dict = $temp$dict;
						continue get;
				}
			}
		}
	});
var $elm$core$Dict$Black = 1;
var $elm$core$Dict$RBNode_elm_builtin = F5(
	function (a, b, c, d, e) {
		return {$: -1, a: a, b: b, c: c, d: d, e: e};
	});
var $elm$core$Dict$Red = 0;
var $elm$core$Dict$balance = F5(
	function (color, key, value, left, right) {
		if ((right.$ === -1) && (!right.a)) {
			var _v1 = right.a;
			var rK = right.b;
			var rV = right.c;
			var rLeft = right.d;
			var rRight = right.e;
			if ((left.$ === -1) && (!left.a)) {
				var _v3 = left.a;
				var lK = left.b;
				var lV = left.c;
				var lLeft = left.d;
				var lRight = left.e;
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					0,
					key,
					value,
					A5($elm$core$Dict$RBNode_elm_builtin, 1, lK, lV, lLeft, lRight),
					A5($elm$core$Dict$RBNode_elm_builtin, 1, rK, rV, rLeft, rRight));
			} else {
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					color,
					rK,
					rV,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, key, value, left, rLeft),
					rRight);
			}
		} else {
			if ((((left.$ === -1) && (!left.a)) && (left.d.$ === -1)) && (!left.d.a)) {
				var _v5 = left.a;
				var lK = left.b;
				var lV = left.c;
				var _v6 = left.d;
				var _v7 = _v6.a;
				var llK = _v6.b;
				var llV = _v6.c;
				var llLeft = _v6.d;
				var llRight = _v6.e;
				var lRight = left.e;
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					0,
					lK,
					lV,
					A5($elm$core$Dict$RBNode_elm_builtin, 1, llK, llV, llLeft, llRight),
					A5($elm$core$Dict$RBNode_elm_builtin, 1, key, value, lRight, right));
			} else {
				return A5($elm$core$Dict$RBNode_elm_builtin, color, key, value, left, right);
			}
		}
	});
var $elm$core$Dict$insertHelp = F3(
	function (key, value, dict) {
		if (dict.$ === -2) {
			return A5($elm$core$Dict$RBNode_elm_builtin, 0, key, value, $elm$core$Dict$RBEmpty_elm_builtin, $elm$core$Dict$RBEmpty_elm_builtin);
		} else {
			var nColor = dict.a;
			var nKey = dict.b;
			var nValue = dict.c;
			var nLeft = dict.d;
			var nRight = dict.e;
			var _v1 = A2($elm$core$Basics$compare, key, nKey);
			switch (_v1) {
				case 0:
					return A5(
						$elm$core$Dict$balance,
						nColor,
						nKey,
						nValue,
						A3($elm$core$Dict$insertHelp, key, value, nLeft),
						nRight);
				case 1:
					return A5($elm$core$Dict$RBNode_elm_builtin, nColor, nKey, value, nLeft, nRight);
				default:
					return A5(
						$elm$core$Dict$balance,
						nColor,
						nKey,
						nValue,
						nLeft,
						A3($elm$core$Dict$insertHelp, key, value, nRight));
			}
		}
	});
var $elm$core$Dict$insert = F3(
	function (key, value, dict) {
		var _v0 = A3($elm$core$Dict$insertHelp, key, value, dict);
		if ((_v0.$ === -1) && (!_v0.a)) {
			var _v1 = _v0.a;
			var k = _v0.b;
			var v = _v0.c;
			var l = _v0.d;
			var r = _v0.e;
			return A5($elm$core$Dict$RBNode_elm_builtin, 1, k, v, l, r);
		} else {
			var x = _v0;
			return x;
		}
	});
var $elm$core$Dict$getMin = function (dict) {
	getMin:
	while (true) {
		if ((dict.$ === -1) && (dict.d.$ === -1)) {
			var left = dict.d;
			var $temp$dict = left;
			dict = $temp$dict;
			continue getMin;
		} else {
			return dict;
		}
	}
};
var $elm$core$Dict$moveRedLeft = function (dict) {
	if (((dict.$ === -1) && (dict.d.$ === -1)) && (dict.e.$ === -1)) {
		if ((dict.e.d.$ === -1) && (!dict.e.d.a)) {
			var clr = dict.a;
			var k = dict.b;
			var v = dict.c;
			var _v1 = dict.d;
			var lClr = _v1.a;
			var lK = _v1.b;
			var lV = _v1.c;
			var lLeft = _v1.d;
			var lRight = _v1.e;
			var _v2 = dict.e;
			var rClr = _v2.a;
			var rK = _v2.b;
			var rV = _v2.c;
			var rLeft = _v2.d;
			var _v3 = rLeft.a;
			var rlK = rLeft.b;
			var rlV = rLeft.c;
			var rlL = rLeft.d;
			var rlR = rLeft.e;
			var rRight = _v2.e;
			return A5(
				$elm$core$Dict$RBNode_elm_builtin,
				0,
				rlK,
				rlV,
				A5(
					$elm$core$Dict$RBNode_elm_builtin,
					1,
					k,
					v,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, lK, lV, lLeft, lRight),
					rlL),
				A5($elm$core$Dict$RBNode_elm_builtin, 1, rK, rV, rlR, rRight));
		} else {
			var clr = dict.a;
			var k = dict.b;
			var v = dict.c;
			var _v4 = dict.d;
			var lClr = _v4.a;
			var lK = _v4.b;
			var lV = _v4.c;
			var lLeft = _v4.d;
			var lRight = _v4.e;
			var _v5 = dict.e;
			var rClr = _v5.a;
			var rK = _v5.b;
			var rV = _v5.c;
			var rLeft = _v5.d;
			var rRight = _v5.e;
			if (clr === 1) {
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					1,
					k,
					v,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, lK, lV, lLeft, lRight),
					A5($elm$core$Dict$RBNode_elm_builtin, 0, rK, rV, rLeft, rRight));
			} else {
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					1,
					k,
					v,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, lK, lV, lLeft, lRight),
					A5($elm$core$Dict$RBNode_elm_builtin, 0, rK, rV, rLeft, rRight));
			}
		}
	} else {
		return dict;
	}
};
var $elm$core$Dict$moveRedRight = function (dict) {
	if (((dict.$ === -1) && (dict.d.$ === -1)) && (dict.e.$ === -1)) {
		if ((dict.d.d.$ === -1) && (!dict.d.d.a)) {
			var clr = dict.a;
			var k = dict.b;
			var v = dict.c;
			var _v1 = dict.d;
			var lClr = _v1.a;
			var lK = _v1.b;
			var lV = _v1.c;
			var _v2 = _v1.d;
			var _v3 = _v2.a;
			var llK = _v2.b;
			var llV = _v2.c;
			var llLeft = _v2.d;
			var llRight = _v2.e;
			var lRight = _v1.e;
			var _v4 = dict.e;
			var rClr = _v4.a;
			var rK = _v4.b;
			var rV = _v4.c;
			var rLeft = _v4.d;
			var rRight = _v4.e;
			return A5(
				$elm$core$Dict$RBNode_elm_builtin,
				0,
				lK,
				lV,
				A5($elm$core$Dict$RBNode_elm_builtin, 1, llK, llV, llLeft, llRight),
				A5(
					$elm$core$Dict$RBNode_elm_builtin,
					1,
					k,
					v,
					lRight,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, rK, rV, rLeft, rRight)));
		} else {
			var clr = dict.a;
			var k = dict.b;
			var v = dict.c;
			var _v5 = dict.d;
			var lClr = _v5.a;
			var lK = _v5.b;
			var lV = _v5.c;
			var lLeft = _v5.d;
			var lRight = _v5.e;
			var _v6 = dict.e;
			var rClr = _v6.a;
			var rK = _v6.b;
			var rV = _v6.c;
			var rLeft = _v6.d;
			var rRight = _v6.e;
			if (clr === 1) {
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					1,
					k,
					v,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, lK, lV, lLeft, lRight),
					A5($elm$core$Dict$RBNode_elm_builtin, 0, rK, rV, rLeft, rRight));
			} else {
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					1,
					k,
					v,
					A5($elm$core$Dict$RBNode_elm_builtin, 0, lK, lV, lLeft, lRight),
					A5($elm$core$Dict$RBNode_elm_builtin, 0, rK, rV, rLeft, rRight));
			}
		}
	} else {
		return dict;
	}
};
var $elm$core$Dict$removeHelpPrepEQGT = F7(
	function (targetKey, dict, color, key, value, left, right) {
		if ((left.$ === -1) && (!left.a)) {
			var _v1 = left.a;
			var lK = left.b;
			var lV = left.c;
			var lLeft = left.d;
			var lRight = left.e;
			return A5(
				$elm$core$Dict$RBNode_elm_builtin,
				color,
				lK,
				lV,
				lLeft,
				A5($elm$core$Dict$RBNode_elm_builtin, 0, key, value, lRight, right));
		} else {
			_v2$2:
			while (true) {
				if ((right.$ === -1) && (right.a === 1)) {
					if (right.d.$ === -1) {
						if (right.d.a === 1) {
							var _v3 = right.a;
							var _v4 = right.d;
							var _v5 = _v4.a;
							return $elm$core$Dict$moveRedRight(dict);
						} else {
							break _v2$2;
						}
					} else {
						var _v6 = right.a;
						var _v7 = right.d;
						return $elm$core$Dict$moveRedRight(dict);
					}
				} else {
					break _v2$2;
				}
			}
			return dict;
		}
	});
var $elm$core$Dict$removeMin = function (dict) {
	if ((dict.$ === -1) && (dict.d.$ === -1)) {
		var color = dict.a;
		var key = dict.b;
		var value = dict.c;
		var left = dict.d;
		var lColor = left.a;
		var lLeft = left.d;
		var right = dict.e;
		if (lColor === 1) {
			if ((lLeft.$ === -1) && (!lLeft.a)) {
				var _v3 = lLeft.a;
				return A5(
					$elm$core$Dict$RBNode_elm_builtin,
					color,
					key,
					value,
					$elm$core$Dict$removeMin(left),
					right);
			} else {
				var _v4 = $elm$core$Dict$moveRedLeft(dict);
				if (_v4.$ === -1) {
					var nColor = _v4.a;
					var nKey = _v4.b;
					var nValue = _v4.c;
					var nLeft = _v4.d;
					var nRight = _v4.e;
					return A5(
						$elm$core$Dict$balance,
						nColor,
						nKey,
						nValue,
						$elm$core$Dict$removeMin(nLeft),
						nRight);
				} else {
					return $elm$core$Dict$RBEmpty_elm_builtin;
				}
			}
		} else {
			return A5(
				$elm$core$Dict$RBNode_elm_builtin,
				color,
				key,
				value,
				$elm$core$Dict$removeMin(left),
				right);
		}
	} else {
		return $elm$core$Dict$RBEmpty_elm_builtin;
	}
};
var $elm$core$Dict$removeHelp = F2(
	function (targetKey, dict) {
		if (dict.$ === -2) {
			return $elm$core$Dict$RBEmpty_elm_builtin;
		} else {
			var color = dict.a;
			var key = dict.b;
			var value = dict.c;
			var left = dict.d;
			var right = dict.e;
			if (_Utils_cmp(targetKey, key) < 0) {
				if ((left.$ === -1) && (left.a === 1)) {
					var _v4 = left.a;
					var lLeft = left.d;
					if ((lLeft.$ === -1) && (!lLeft.a)) {
						var _v6 = lLeft.a;
						return A5(
							$elm$core$Dict$RBNode_elm_builtin,
							color,
							key,
							value,
							A2($elm$core$Dict$removeHelp, targetKey, left),
							right);
					} else {
						var _v7 = $elm$core$Dict$moveRedLeft(dict);
						if (_v7.$ === -1) {
							var nColor = _v7.a;
							var nKey = _v7.b;
							var nValue = _v7.c;
							var nLeft = _v7.d;
							var nRight = _v7.e;
							return A5(
								$elm$core$Dict$balance,
								nColor,
								nKey,
								nValue,
								A2($elm$core$Dict$removeHelp, targetKey, nLeft),
								nRight);
						} else {
							return $elm$core$Dict$RBEmpty_elm_builtin;
						}
					}
				} else {
					return A5(
						$elm$core$Dict$RBNode_elm_builtin,
						color,
						key,
						value,
						A2($elm$core$Dict$removeHelp, targetKey, left),
						right);
				}
			} else {
				return A2(
					$elm$core$Dict$removeHelpEQGT,
					targetKey,
					A7($elm$core$Dict$removeHelpPrepEQGT, targetKey, dict, color, key, value, left, right));
			}
		}
	});
var $elm$core$Dict$removeHelpEQGT = F2(
	function (targetKey, dict) {
		if (dict.$ === -1) {
			var color = dict.a;
			var key = dict.b;
			var value = dict.c;
			var left = dict.d;
			var right = dict.e;
			if (_Utils_eq(targetKey, key)) {
				var _v1 = $elm$core$Dict$getMin(right);
				if (_v1.$ === -1) {
					var minKey = _v1.b;
					var minValue = _v1.c;
					return A5(
						$elm$core$Dict$balance,
						color,
						minKey,
						minValue,
						left,
						$elm$core$Dict$removeMin(right));
				} else {
					return $elm$core$Dict$RBEmpty_elm_builtin;
				}
			} else {
				return A5(
					$elm$core$Dict$balance,
					color,
					key,
					value,
					left,
					A2($elm$core$Dict$removeHelp, targetKey, right));
			}
		} else {
			return $elm$core$Dict$RBEmpty_elm_builtin;
		}
	});
var $elm$core$Dict$remove = F2(
	function (key, dict) {
		var _v0 = A2($elm$core$Dict$removeHelp, key, dict);
		if ((_v0.$ === -1) && (!_v0.a)) {
			var _v1 = _v0.a;
			var k = _v0.b;
			var v = _v0.c;
			var l = _v0.d;
			var r = _v0.e;
			return A5($elm$core$Dict$RBNode_elm_builtin, 1, k, v, l, r);
		} else {
			var x = _v0;
			return x;
		}
	});
var $elm$core$Dict$update = F3(
	function (targetKey, alter, dictionary) {
		var _v0 = alter(
			A2($elm$core$Dict$get, targetKey, dictionary));
		if (!_v0.$) {
			var value = _v0.a;
			return A3($elm$core$Dict$insert, targetKey, value, dictionary);
		} else {
			return A2($elm$core$Dict$remove, targetKey, dictionary);
		}
	});
var $elm$http$Http$emptyBody = _Http_emptyBody;
var $elm$json$Json$Decode$list = _Json_decodeList;
var $elm$json$Json$Decode$oneOf = _Json_oneOf;
var $author$project$Main$Activities = 6;
var $author$project$Main$Camp = 2;
var $author$project$Main$Ferry = 3;
var $author$project$Main$Food = 1;
var $author$project$Main$Fuel = 0;
var $author$project$Main$Gear = 4;
var $author$project$Main$Lodging = 5;
var $author$project$Main$Medical = 8;
var $author$project$Main$Misc = 10;
var $author$project$Main$Shopping = 7;
var $author$project$Main$Transport = 9;
var $author$project$Main$categoryFromString = function (s) {
	switch (s) {
		case 'fuel':
			return 0;
		case 'food':
			return 1;
		case 'camp':
			return 2;
		case 'ferry':
			return 3;
		case 'gear':
			return 4;
		case 'lodging':
			return 5;
		case 'activities':
			return 6;
		case 'shopping':
			return 7;
		case 'medical':
			return 8;
		case 'transport':
			return 9;
		default:
			return 10;
	}
};
var $author$project$Json$Decode$Pipeline$custom = $elm$json$Json$Decode$map2($elm$core$Basics$apR);
var $elm$json$Json$Decode$index = _Json_decodeIndex;
var $author$project$Main$optIndex = F3(
	function (i, decoder, fallback) {
		return $elm$json$Json$Decode$oneOf(
			_List_fromArray(
				[
					A2($elm$json$Json$Decode$index, i, decoder),
					$elm$json$Json$Decode$succeed(fallback)
				]));
	});
var $elm$core$String$toFloat = _String_toFloat;
var $author$project$Main$optMaybeFloat = function (i) {
	return $elm$json$Json$Decode$oneOf(
		_List_fromArray(
			[
				A2(
				$elm$json$Json$Decode$index,
				i,
				A2(
					$elm$json$Json$Decode$andThen,
					function (s) {
						return (s === '') ? $elm$json$Json$Decode$succeed($elm$core$Maybe$Nothing) : $elm$json$Json$Decode$succeed(
							$elm$core$String$toFloat(s));
					},
					$elm$json$Json$Decode$string)),
				$elm$json$Json$Decode$succeed($elm$core$Maybe$Nothing)
			]));
};
var $author$project$Main$parseAmountStr = function (s) {
	var _v0 = $elm$core$String$toFloat(s);
	if (!_v0.$) {
		var f = _v0.a;
		return $elm$json$Json$Decode$succeed(f);
	} else {
		return $elm$json$Json$Decode$succeed(0.0);
	}
};
var $author$project$Main$rowDecoder = A2(
	$author$project$Json$Decode$Pipeline$custom,
	A3($author$project$Main$optIndex, 9, $elm$json$Json$Decode$string, ''),
	A2(
		$author$project$Json$Decode$Pipeline$custom,
		$author$project$Main$optMaybeFloat(8),
		A2(
			$author$project$Json$Decode$Pipeline$custom,
			$author$project$Main$optMaybeFloat(7),
			A2(
				$author$project$Json$Decode$Pipeline$custom,
				A3($author$project$Main$optIndex, 6, $elm$json$Json$Decode$string, ''),
				A2(
					$author$project$Json$Decode$Pipeline$custom,
					A3($author$project$Main$optIndex, 5, $elm$json$Json$Decode$string, ''),
					A2(
						$author$project$Json$Decode$Pipeline$custom,
						A3($author$project$Main$optIndex, 4, $elm$json$Json$Decode$string, ''),
						A2(
							$author$project$Json$Decode$Pipeline$custom,
							A2(
								$elm$json$Json$Decode$index,
								3,
								A2($elm$json$Json$Decode$map, $author$project$Main$categoryFromString, $elm$json$Json$Decode$string)),
							A2(
								$author$project$Json$Decode$Pipeline$custom,
								A2(
									$elm$json$Json$Decode$index,
									2,
									A2($elm$json$Json$Decode$andThen, $author$project$Main$parseAmountStr, $elm$json$Json$Decode$string)),
								A2(
									$author$project$Json$Decode$Pipeline$custom,
									A2($elm$json$Json$Decode$index, 1, $elm$json$Json$Decode$string),
									A2(
										$author$project$Json$Decode$Pipeline$custom,
										A2($elm$json$Json$Decode$index, 0, $elm$json$Json$Decode$string),
										$elm$json$Json$Decode$succeed(
											function (id) {
												return function (date) {
													return function (amount) {
														return function (category) {
															return function (note) {
																return function (merchant) {
																	return function (createdAt) {
																		return function (lat) {
																			return function (lon) {
																				return function (longNote) {
																					return {d: amount, h: category, a_: createdAt, i: date, E: id, M: lat, P: lon, r: longNote, k: merchant, m: note, aK: 0};
																				};
																			};
																		};
																	};
																};
															};
														};
													};
												};
											})))))))))));
var $author$project$Main$entriesDecoder = $elm$json$Json$Decode$oneOf(
	_List_fromArray(
		[
			A2(
			$elm$json$Json$Decode$map,
			$elm$core$List$indexedMap(
				F2(
					function (i, e) {
						return _Utils_update(
							e,
							{aK: i + 2});
					})),
			A2(
				$elm$json$Json$Decode$field,
				'values',
				$elm$json$Json$Decode$list($author$project$Main$rowDecoder))),
			$elm$json$Json$Decode$succeed(_List_Nil)
		]));
var $elm$http$Http$BadBody = function (a) {
	return {$: 4, a: a};
};
var $elm$http$Http$BadStatus = function (a) {
	return {$: 3, a: a};
};
var $elm$http$Http$BadUrl = function (a) {
	return {$: 0, a: a};
};
var $elm$http$Http$NetworkError = {$: 2};
var $elm$http$Http$Timeout = {$: 1};
var $elm$json$Json$Decode$decodeString = _Json_runOnString;
var $elm$core$Basics$composeR = F3(
	function (f, g, x) {
		return g(
			f(x));
	});
var $elm$http$Http$expectStringResponse = F2(
	function (toMsg, toResult) {
		return A3(
			_Http_expect,
			'',
			$elm$core$Basics$identity,
			A2($elm$core$Basics$composeR, toResult, toMsg));
	});
var $author$project$Main$expectJsonBody = F2(
	function (toMsg, decoder) {
		return A2(
			$elm$http$Http$expectStringResponse,
			toMsg,
			function (response) {
				switch (response.$) {
					case 0:
						var u = response.a;
						return $elm$core$Result$Err(
							$elm$http$Http$BadUrl(u));
					case 1:
						return $elm$core$Result$Err($elm$http$Http$Timeout);
					case 2:
						return $elm$core$Result$Err($elm$http$Http$NetworkError);
					case 3:
						var meta = response.a;
						var body = response.b;
						return (meta.bu === 401) ? $elm$core$Result$Err(
							$elm$http$Http$BadStatus(401)) : $elm$core$Result$Err(
							$elm$http$Http$BadBody(
								$elm$core$String$fromInt(meta.bu) + (' ' + body)));
					default:
						var body = response.b;
						var _v1 = A2($elm$json$Json$Decode$decodeString, decoder, body);
						if (!_v1.$) {
							var v = _v1.a;
							return $elm$core$Result$Ok(v);
						} else {
							var e = _v1.a;
							return $elm$core$Result$Err(
								$elm$http$Http$BadBody(
									$elm$json$Json$Decode$errorToString(e)));
						}
				}
			});
	});
var $elm$http$Http$Header = F2(
	function (a, b) {
		return {$: 0, a: a, b: b};
	});
var $elm$http$Http$header = $elm$http$Http$Header;
var $elm$http$Http$Request = function (a) {
	return {$: 1, a: a};
};
var $elm$http$Http$State = F2(
	function (reqs, subs) {
		return {cM: reqs, cW: subs};
	});
var $elm$http$Http$init = $elm$core$Task$succeed(
	A2($elm$http$Http$State, $elm$core$Dict$empty, _List_Nil));
var $elm$core$Process$kill = _Scheduler_kill;
var $elm$core$Process$spawn = _Scheduler_spawn;
var $elm$http$Http$updateReqs = F3(
	function (router, cmds, reqs) {
		updateReqs:
		while (true) {
			if (!cmds.b) {
				return $elm$core$Task$succeed(reqs);
			} else {
				var cmd = cmds.a;
				var otherCmds = cmds.b;
				if (!cmd.$) {
					var tracker = cmd.a;
					var _v2 = A2($elm$core$Dict$get, tracker, reqs);
					if (_v2.$ === 1) {
						var $temp$router = router,
							$temp$cmds = otherCmds,
							$temp$reqs = reqs;
						router = $temp$router;
						cmds = $temp$cmds;
						reqs = $temp$reqs;
						continue updateReqs;
					} else {
						var pid = _v2.a;
						return A2(
							$elm$core$Task$andThen,
							function (_v3) {
								return A3(
									$elm$http$Http$updateReqs,
									router,
									otherCmds,
									A2($elm$core$Dict$remove, tracker, reqs));
							},
							$elm$core$Process$kill(pid));
					}
				} else {
					var req = cmd.a;
					return A2(
						$elm$core$Task$andThen,
						function (pid) {
							var _v4 = req.be;
							if (_v4.$ === 1) {
								return A3($elm$http$Http$updateReqs, router, otherCmds, reqs);
							} else {
								var tracker = _v4.a;
								return A3(
									$elm$http$Http$updateReqs,
									router,
									otherCmds,
									A3($elm$core$Dict$insert, tracker, pid, reqs));
							}
						},
						$elm$core$Process$spawn(
							A3(
								_Http_toTask,
								router,
								$elm$core$Platform$sendToApp(router),
								req)));
				}
			}
		}
	});
var $elm$http$Http$onEffects = F4(
	function (router, cmds, subs, state) {
		return A2(
			$elm$core$Task$andThen,
			function (reqs) {
				return $elm$core$Task$succeed(
					A2($elm$http$Http$State, reqs, subs));
			},
			A3($elm$http$Http$updateReqs, router, cmds, state.cM));
	});
var $elm$core$List$maybeCons = F3(
	function (f, mx, xs) {
		var _v0 = f(mx);
		if (!_v0.$) {
			var x = _v0.a;
			return A2($elm$core$List$cons, x, xs);
		} else {
			return xs;
		}
	});
var $elm$core$List$filterMap = F2(
	function (f, xs) {
		return A3(
			$elm$core$List$foldr,
			$elm$core$List$maybeCons(f),
			_List_Nil,
			xs);
	});
var $elm$http$Http$maybeSend = F4(
	function (router, desiredTracker, progress, _v0) {
		var actualTracker = _v0.a;
		var toMsg = _v0.b;
		return _Utils_eq(desiredTracker, actualTracker) ? $elm$core$Maybe$Just(
			A2(
				$elm$core$Platform$sendToApp,
				router,
				toMsg(progress))) : $elm$core$Maybe$Nothing;
	});
var $elm$http$Http$onSelfMsg = F3(
	function (router, _v0, state) {
		var tracker = _v0.a;
		var progress = _v0.b;
		return A2(
			$elm$core$Task$andThen,
			function (_v1) {
				return $elm$core$Task$succeed(state);
			},
			$elm$core$Task$sequence(
				A2(
					$elm$core$List$filterMap,
					A3($elm$http$Http$maybeSend, router, tracker, progress),
					state.cW)));
	});
var $elm$http$Http$Cancel = function (a) {
	return {$: 0, a: a};
};
var $elm$http$Http$cmdMap = F2(
	function (func, cmd) {
		if (!cmd.$) {
			var tracker = cmd.a;
			return $elm$http$Http$Cancel(tracker);
		} else {
			var r = cmd.a;
			return $elm$http$Http$Request(
				{
					c8: r.c8,
					aZ: r.aZ,
					a2: A2(_Http_mapExpect, func, r.a2),
					a4: r.a4,
					a7: r.a7,
					bb: r.bb,
					be: r.be,
					bh: r.bh
				});
		}
	});
var $elm$http$Http$MySub = F2(
	function (a, b) {
		return {$: 0, a: a, b: b};
	});
var $elm$http$Http$subMap = F2(
	function (func, _v0) {
		var tracker = _v0.a;
		var toMsg = _v0.b;
		return A2(
			$elm$http$Http$MySub,
			tracker,
			A2($elm$core$Basics$composeR, toMsg, func));
	});
_Platform_effectManagers['Http'] = _Platform_createManager($elm$http$Http$init, $elm$http$Http$onEffects, $elm$http$Http$onSelfMsg, $elm$http$Http$cmdMap, $elm$http$Http$subMap);
var $elm$http$Http$command = _Platform_leaf('Http');
var $elm$http$Http$subscription = _Platform_leaf('Http');
var $elm$http$Http$request = function (r) {
	return $elm$http$Http$command(
		$elm$http$Http$Request(
			{c8: false, aZ: r.aZ, a2: r.a2, a4: r.a4, a7: r.a7, bb: r.bb, be: r.be, bh: r.bh}));
};
var $author$project$Main$fetchEntries = F2(
	function (creds, sheetId) {
		return $elm$http$Http$request(
			{
				aZ: $elm$http$Http$emptyBody,
				a2: A2($author$project$Main$expectJsonBody, $author$project$Main$EntriesFetched, $author$project$Main$entriesDecoder),
				a4: _List_fromArray(
					[
						A2($elm$http$Http$header, 'Authorization', 'Bearer ' + creds.ap)
					]),
				a7: 'GET',
				bb: $elm$core$Maybe$Nothing,
				be: $elm$core$Maybe$Nothing,
				bh: 'https://sheets.googleapis.com/v4/spreadsheets/' + (sheetId + '/values/Expenses!A2:J')
			});
	});
var $elm$json$Json$Decode$maybe = function (decoder) {
	return $elm$json$Json$Decode$oneOf(
		_List_fromArray(
			[
				A2($elm$json$Json$Decode$map, $elm$core$Maybe$Just, decoder),
				$elm$json$Json$Decode$succeed($elm$core$Maybe$Nothing)
			]));
};
var $elm$core$Basics$neq = _Utils_notEqual;
var $elm$core$Platform$Cmd$batch = _Platform_batch;
var $elm$core$Platform$Cmd$none = $elm$core$Platform$Cmd$batch(_List_Nil);
var $author$project$Main$LedgerTab = 2;
var $author$project$Main$LocationIdle = {$: 0};
var $author$project$Main$defaultPendingEntry = function (today) {
	return {d: '', h: 0, i: today, J: $author$project$Main$LocationIdle, r: '', k: '', m: ''};
};
var $author$project$Main$toAuthState = F2(
	function (creds, gs) {
		return {
			aq: $elm$core$Maybe$Nothing,
			c: gs.s.c,
			ag: creds,
			as: $elm$core$Maybe$Nothing,
			U: _List_Nil,
			ai: $elm$core$Maybe$Nothing,
			a3: false,
			at: gs.s.c.t !== '',
			l: $author$project$Main$defaultPendingEntry(gs.K),
			n: _List_Nil,
			aS: false,
			aL: false,
			aw: false,
			Y: 2,
			aV: $elm$core$Maybe$Nothing,
			K: gs.K,
			ac: gs.ac
		};
	});
var $elm$core$Result$withDefault = F2(
	function (def, result) {
		if (!result.$) {
			var a = result.a;
			return a;
		} else {
			return def;
		}
	});
var $author$project$Main$init = function (flagsJson) {
	var token = A2(
		$elm$core$Maybe$andThen,
		function (t) {
			return (t === '') ? $elm$core$Maybe$Nothing : $elm$core$Maybe$Just(t);
		},
		A2(
			$elm$core$Result$withDefault,
			$elm$core$Maybe$Nothing,
			A2(
				$elm$json$Json$Decode$decodeValue,
				$elm$json$Json$Decode$maybe(
					A2($elm$json$Json$Decode$field, 'token', $elm$json$Json$Decode$string)),
				flagsJson)));
	var dec = function (field_) {
		return A2(
			$elm$core$Result$withDefault,
			'',
			A2(
				$elm$json$Json$Decode$decodeValue,
				A2($elm$json$Json$Decode$field, field_, $elm$json$Json$Decode$string),
				flagsJson));
	};
	var cfg = {
		ae: dec('anthropicKey'),
		az: dec('googleClientId'),
		t: dec('sheetId'),
		ax: function (s) {
			return (s === '') ? '2026-05-22' : s;
		}(
			dec('tripStart'))
	};
	var gs = {
		s: {c: cfg, aI: 0},
		aC: false,
		K: dec('today'),
		ac: dec('version')
	};
	if (token.$ === 1) {
		return _Utils_Tuple2(
			$author$project$Main$GuestModel(gs),
			$elm$core$Platform$Cmd$none);
	} else {
		var t = token.a;
		var as_ = A2(
			$author$project$Main$toAuthState,
			{ap: t},
			gs);
		return _Utils_Tuple2(
			$author$project$Main$AuthModel(as_),
			(cfg.t !== '') ? A2(
				$author$project$Main$fetchEntries,
				{ap: t},
				cfg.t) : $elm$core$Platform$Cmd$none);
	}
};
var $author$project$Main$AddTab = 1;
var $author$project$Main$BrowserGeo = 1;
var $author$project$Main$ExifGps = 0;
var $author$project$Main$GotFileUrl = F2(
	function (a, b) {
		return {$: 9, a: a, b: b};
	});
var $author$project$Main$GotSubmitTime = function (a) {
	return {$: 21, a: a};
};
var $author$project$Main$LocationFetching = {$: 1};
var $author$project$Main$LocationGot = F3(
	function (a, b, c) {
		return {$: 4, a: a, b: b, c: c};
	});
var $author$project$Main$LocationNoExifGps = {$: 3};
var $author$project$Main$LocationSkipped = {$: 5};
var $author$project$Main$ManualPin = 2;
var $author$project$Main$ScanProcessing = 1;
var $author$project$Main$ScanReady = 2;
var $author$project$Main$ScanSubmitted = 3;
var $author$project$Main$ScanTab = 0;
var $author$project$Main$SessionExpired = 1;
var $elm$core$List$any = F2(
	function (isOkay, list) {
		any:
		while (true) {
			if (!list.b) {
				return false;
			} else {
				var x = list.a;
				var xs = list.b;
				if (isOkay(x)) {
					return true;
				} else {
					var $temp$isOkay = isOkay,
						$temp$list = xs;
					isOkay = $temp$isOkay;
					list = $temp$list;
					continue any;
				}
			}
		}
	});
var $author$project$Main$EntrySubmitted = function (a) {
	return {$: 22, a: a};
};
var $author$project$Main$categoryLabel = function (cat) {
	switch (cat) {
		case 0:
			return 'fuel';
		case 1:
			return 'food';
		case 2:
			return 'camp';
		case 3:
			return 'ferry';
		case 4:
			return 'gear';
		case 5:
			return 'lodging';
		case 6:
			return 'activities';
		case 7:
			return 'shopping';
		case 8:
			return 'medical';
		case 9:
			return 'transport';
		default:
			return 'misc';
	}
};
var $author$project$Main$expectWhateverBody = function (toMsg) {
	return A2(
		$elm$http$Http$expectStringResponse,
		toMsg,
		function (response) {
			switch (response.$) {
				case 0:
					var u = response.a;
					return $elm$core$Result$Err(
						$elm$http$Http$BadUrl(u));
				case 1:
					return $elm$core$Result$Err($elm$http$Http$Timeout);
				case 2:
					return $elm$core$Result$Err($elm$http$Http$NetworkError);
				case 3:
					var meta = response.a;
					var body = response.b;
					return (meta.bu === 401) ? $elm$core$Result$Err(
						$elm$http$Http$BadStatus(401)) : $elm$core$Result$Err(
						$elm$http$Http$BadBody(
							$elm$core$String$fromInt(meta.bu) + (' ' + body)));
				default:
					return $elm$core$Result$Ok(0);
			}
		});
};
var $elm$json$Json$Encode$float = _Json_wrap;
var $elm$core$String$fromFloat = _String_fromNumber;
var $elm$http$Http$jsonBody = function (value) {
	return A2(
		_Http_pair,
		'application/json',
		A2($elm$json$Json$Encode$encode, 0, value));
};
var $elm$json$Json$Encode$list = F2(
	function (func, entries) {
		return _Json_wrap(
			A3(
				$elm$core$List$foldl,
				_Json_addEntry(func),
				_Json_emptyArray(0),
				entries));
	});
var $elm$core$Maybe$map = F2(
	function (f, maybe) {
		if (!maybe.$) {
			var value = maybe.a;
			return $elm$core$Maybe$Just(
				f(value));
		} else {
			return $elm$core$Maybe$Nothing;
		}
	});
var $elm$json$Json$Encode$object = function (pairs) {
	return _Json_wrap(
		A3(
			$elm$core$List$foldl,
			F2(
				function (_v0, obj) {
					var k = _v0.a;
					var v = _v0.b;
					return A3(_Json_addField, k, v, obj);
				}),
			_Json_emptyObject(0),
			pairs));
};
var $elm$json$Json$Encode$string = _Json_wrap;
var $elm$core$Maybe$withDefault = F2(
	function (_default, maybe) {
		if (!maybe.$) {
			var value = maybe.a;
			return value;
		} else {
			return _default;
		}
	});
var $author$project$Main$appendEntry = F3(
	function (creds, sheetId, entry) {
		var body = $elm$json$Json$Encode$object(
			_List_fromArray(
				[
					_Utils_Tuple2(
					'values',
					A2(
						$elm$json$Json$Encode$list,
						$elm$core$Basics$identity,
						_List_fromArray(
							[
								A2(
								$elm$json$Json$Encode$list,
								$elm$core$Basics$identity,
								_List_fromArray(
									[
										$elm$json$Json$Encode$string(entry.E),
										$elm$json$Json$Encode$string(entry.i),
										$elm$json$Json$Encode$float(entry.d),
										$elm$json$Json$Encode$string(
										$author$project$Main$categoryLabel(entry.h)),
										$elm$json$Json$Encode$string(entry.m),
										$elm$json$Json$Encode$string(entry.k),
										$elm$json$Json$Encode$string(entry.a_),
										A2(
										$elm$core$Maybe$withDefault,
										$elm$json$Json$Encode$string(''),
										A2(
											$elm$core$Maybe$map,
											function (v) {
												return $elm$json$Json$Encode$string(
													$elm$core$String$fromFloat(v));
											},
											entry.M)),
										A2(
										$elm$core$Maybe$withDefault,
										$elm$json$Json$Encode$string(''),
										A2(
											$elm$core$Maybe$map,
											function (v) {
												return $elm$json$Json$Encode$string(
													$elm$core$String$fromFloat(v));
											},
											entry.P)),
										$elm$json$Json$Encode$string(entry.r)
									]))
							])))
				]));
		return $elm$http$Http$request(
			{
				aZ: $elm$http$Http$jsonBody(body),
				a2: $author$project$Main$expectWhateverBody($author$project$Main$EntrySubmitted),
				a4: _List_fromArray(
					[
						A2($elm$http$Http$header, 'Authorization', 'Bearer ' + creds.ap)
					]),
				a7: 'POST',
				bb: $elm$core$Maybe$Nothing,
				be: $elm$core$Maybe$Nothing,
				bh: 'https://sheets.googleapis.com/v4/spreadsheets/' + (sheetId + '/values/Expenses!A:J:append?valueInputOption=RAW')
			});
	});
var $author$project$Main$authPending = F2(
	function (f, as_) {
		return _Utils_Tuple2(
			$author$project$Main$AuthModel(
				_Utils_update(
					as_,
					{
						l: f(as_.l)
					})),
			$elm$core$Platform$Cmd$none);
	});
var $author$project$Main$claudeTextDecoder = A2(
	$elm$json$Json$Decode$field,
	'content',
	A2(
		$elm$json$Json$Decode$index,
		0,
		A2($elm$json$Json$Decode$field, 'text', $elm$json$Json$Decode$string)));
var $elm$json$Json$Encode$null = _Json_encodeNull;
var $author$project$Main$clearAllStorage = _Platform_outgoingPort(
	'clearAllStorage',
	function ($) {
		return $elm$json$Json$Encode$null;
	});
var $author$project$Main$clearStorage = _Platform_outgoingPort(
	'clearStorage',
	function ($) {
		return $elm$json$Json$Encode$null;
	});
var $author$project$Main$EntryDeleted = function (a) {
	return {$: 25, a: a};
};
var $elm$json$Json$Encode$int = _Json_wrap;
var $author$project$Main$deleteEntry = F3(
	function (creds, sheetId, rowIndex) {
		var body = $elm$json$Json$Encode$object(
			_List_fromArray(
				[
					_Utils_Tuple2(
					'requests',
					A2(
						$elm$json$Json$Encode$list,
						$elm$core$Basics$identity,
						_List_fromArray(
							[
								$elm$json$Json$Encode$object(
								_List_fromArray(
									[
										_Utils_Tuple2(
										'deleteDimension',
										$elm$json$Json$Encode$object(
											_List_fromArray(
												[
													_Utils_Tuple2(
													'range',
													$elm$json$Json$Encode$object(
														_List_fromArray(
															[
																_Utils_Tuple2(
																'sheetId',
																$elm$json$Json$Encode$int(0)),
																_Utils_Tuple2(
																'dimension',
																$elm$json$Json$Encode$string('ROWS')),
																_Utils_Tuple2(
																'startIndex',
																$elm$json$Json$Encode$int(rowIndex - 1)),
																_Utils_Tuple2(
																'endIndex',
																$elm$json$Json$Encode$int(rowIndex))
															])))
												])))
									]))
							])))
				]));
		return $elm$http$Http$request(
			{
				aZ: $elm$http$Http$jsonBody(body),
				a2: $author$project$Main$expectWhateverBody($author$project$Main$EntryDeleted),
				a4: _List_fromArray(
					[
						A2($elm$http$Http$header, 'Authorization', 'Bearer ' + creds.ap)
					]),
				a7: 'POST',
				bb: $elm$core$Maybe$Nothing,
				be: $elm$core$Maybe$Nothing,
				bh: 'https://sheets.googleapis.com/v4/spreadsheets/' + (sheetId + ':batchUpdate')
			});
	});
var $author$project$Main$entryToPending = function (e) {
	return {
		d: $elm$core$String$fromFloat(e.d),
		h: e.h,
		i: e.i,
		J: function () {
			var _v0 = _Utils_Tuple2(e.M, e.P);
			if ((!_v0.a.$) && (!_v0.b.$)) {
				var la = _v0.a.a;
				var lo = _v0.b.a;
				return A3($author$project$Main$LocationGot, la, lo, 2);
			} else {
				return $author$project$Main$LocationIdle;
			}
		}(),
		r: e.r,
		k: e.k,
		m: e.m
	};
};
var $author$project$Main$extractBase64 = function (dataUrl) {
	var _v0 = A2($elm$core$String$split, ',', dataUrl);
	if (_v0.b && _v0.b.b) {
		var _v1 = _v0.b;
		var b64 = _v1.a;
		return b64;
	} else {
		return dataUrl;
	}
};
var $author$project$Main$extractExifGps = _Platform_outgoingPort(
	'extractExifGps',
	function ($) {
		return $elm$json$Json$Encode$object(
			_List_fromArray(
				[
					_Utils_Tuple2(
					'dataUrl',
					$elm$json$Json$Encode$string($.ce)),
					_Utils_Tuple2(
					'id',
					$elm$json$Json$Encode$string($.E))
				]));
	});
var $elm$core$List$filter = F2(
	function (isGood, list) {
		return A3(
			$elm$core$List$foldr,
			F2(
				function (x, xs) {
					return isGood(x) ? A2($elm$core$List$cons, x, xs) : xs;
				}),
			_List_Nil,
			list);
	});
var $author$project$Main$LocationCheckingExif = {$: 2};
var $author$project$Main$ScanQueued = 0;
var $author$project$Main$freshScanItem = function (id) {
	return {a1: '', E: id, a5: '', J: $author$project$Main$LocationCheckingExif, a8: $elm$core$Maybe$Nothing, av: 0};
};
var $author$project$Main$getMimeType = function (dataUrl) {
	return A2($elm$core$String$contains, 'image/png', dataUrl) ? 'image/png' : (A2($elm$core$String$contains, 'image/gif', dataUrl) ? 'image/gif' : (A2($elm$core$String$contains, 'image/webp', dataUrl) ? 'image/webp' : 'image/jpeg'));
};
var $elm$core$List$head = function (list) {
	if (list.b) {
		var x = list.a;
		var xs = list.b;
		return $elm$core$Maybe$Just(x);
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $elm$json$Json$Decode$at = F2(
	function (fields, decoder) {
		return A3($elm$core$List$foldr, $elm$json$Json$Decode$field, decoder, fields);
	});
var $elm$core$String$trimLeft = _String_trimLeft;
var $author$project$Main$httpErrString = function (err) {
	switch (err.$) {
		case 0:
			var u = err.a;
			return 'Bad URL: ' + u;
		case 1:
			return 'Request timed out';
		case 2:
			return 'No network connection';
		case 3:
			if (err.a === 401) {
				return 'Session expired — re-authenticating…';
			} else {
				var code = err.a;
				return 'HTTP ' + $elm$core$String$fromInt(code);
			}
		default:
			var body = err.a;
			var jsonPart = $elm$core$String$trimLeft(
				A2($elm$core$String$dropLeft, 4, body));
			return A2(
				$elm$core$Result$withDefault,
				A2($elm$core$String$left, 160, body),
				A2(
					$elm$json$Json$Decode$decodeString,
					A2(
						$elm$json$Json$Decode$at,
						_List_fromArray(
							['error', 'message']),
						$elm$json$Json$Decode$string),
					jsonPart));
	}
};
var $author$project$Main$GotOcrResult = F2(
	function (a, b) {
		return {$: 10, a: a, b: b};
	});
var $elm$core$Result$mapError = F2(
	function (f, result) {
		if (!result.$) {
			var v = result.a;
			return $elm$core$Result$Ok(v);
		} else {
			var e = result.a;
			return $elm$core$Result$Err(
				f(e));
		}
	});
var $elm$http$Http$resolve = F2(
	function (toResult, response) {
		switch (response.$) {
			case 0:
				var url = response.a;
				return $elm$core$Result$Err(
					$elm$http$Http$BadUrl(url));
			case 1:
				return $elm$core$Result$Err($elm$http$Http$Timeout);
			case 2:
				return $elm$core$Result$Err($elm$http$Http$NetworkError);
			case 3:
				var metadata = response.a;
				return $elm$core$Result$Err(
					$elm$http$Http$BadStatus(metadata.bu));
			default:
				var body = response.b;
				return A2(
					$elm$core$Result$mapError,
					$elm$http$Http$BadBody,
					toResult(body));
		}
	});
var $elm$http$Http$expectString = function (toMsg) {
	return A2(
		$elm$http$Http$expectStringResponse,
		toMsg,
		$elm$http$Http$resolve($elm$core$Result$Ok));
};
var $author$project$Main$ocrSystemPrompt = 'You are a receipt parser. Extract expense info and return ONLY raw valid JSON with no markdown, no code fences, no explanation. Format exactly: {\"amount\": <number>, \"category\": \"<fuel|food|camp|ferry|gear|lodging|activities|shopping|medical|transport|misc>\", \"note\": \"<brief description max 50 chars>\", \"longNote\": \"<detailed description max 280 chars, include what was purchased, where, any relevant context>\", \"merchant\": \"<store name>\", \"date\": \"<YYYY-MM-DD or null if not visible on receipt>\"}. Choose the best matching category.';
var $author$project$Main$makeOcrCall = F4(
	function (itemId, apiKey, base64Data, mimeType) {
		var body = $elm$json$Json$Encode$object(
			_List_fromArray(
				[
					_Utils_Tuple2(
					'model',
					$elm$json$Json$Encode$string('claude-sonnet-4-6')),
					_Utils_Tuple2(
					'max_tokens',
					$elm$json$Json$Encode$int(256)),
					_Utils_Tuple2(
					'system',
					$elm$json$Json$Encode$string($author$project$Main$ocrSystemPrompt)),
					_Utils_Tuple2(
					'messages',
					A2(
						$elm$json$Json$Encode$list,
						$elm$core$Basics$identity,
						_List_fromArray(
							[
								$elm$json$Json$Encode$object(
								_List_fromArray(
									[
										_Utils_Tuple2(
										'role',
										$elm$json$Json$Encode$string('user')),
										_Utils_Tuple2(
										'content',
										A2(
											$elm$json$Json$Encode$list,
											$elm$core$Basics$identity,
											_List_fromArray(
												[
													$elm$json$Json$Encode$object(
													_List_fromArray(
														[
															_Utils_Tuple2(
															'type',
															$elm$json$Json$Encode$string('image')),
															_Utils_Tuple2(
															'source',
															$elm$json$Json$Encode$object(
																_List_fromArray(
																	[
																		_Utils_Tuple2(
																		'type',
																		$elm$json$Json$Encode$string('base64')),
																		_Utils_Tuple2(
																		'media_type',
																		$elm$json$Json$Encode$string(mimeType)),
																		_Utils_Tuple2(
																		'data',
																		$elm$json$Json$Encode$string(base64Data))
																	])))
														])),
													$elm$json$Json$Encode$object(
													_List_fromArray(
														[
															_Utils_Tuple2(
															'type',
															$elm$json$Json$Encode$string('text')),
															_Utils_Tuple2(
															'text',
															$elm$json$Json$Encode$string('Extract the expense info from this receipt.'))
														]))
												])))
									]))
							])))
				]));
		return $elm$http$Http$request(
			{
				aZ: $elm$http$Http$jsonBody(body),
				a2: $elm$http$Http$expectString(
					$author$project$Main$GotOcrResult(itemId)),
				a4: _List_fromArray(
					[
						A2($elm$http$Http$header, 'x-api-key', apiKey),
						A2($elm$http$Http$header, 'anthropic-version', '2023-06-01'),
						A2($elm$http$Http$header, 'anthropic-dangerous-direct-browser-access', 'true')
					]),
				a7: 'POST',
				bb: $elm$core$Maybe$Nothing,
				be: $elm$core$Maybe$Nothing,
				bh: 'https://api.anthropic.com/v1/messages'
			});
	});
var $elm$core$Basics$not = _Basics_not;
var $elm$time$Time$Name = function (a) {
	return {$: 0, a: a};
};
var $elm$time$Time$Offset = function (a) {
	return {$: 1, a: a};
};
var $elm$time$Time$Zone = F2(
	function (a, b) {
		return {$: 0, a: a, b: b};
	});
var $elm$time$Time$customZone = $elm$time$Time$Zone;
var $elm$time$Time$Posix = $elm$core$Basics$identity;
var $elm$time$Time$millisToPosix = $elm$core$Basics$identity;
var $elm$time$Time$now = _Time_now($elm$time$Time$millisToPosix);
var $author$project$Main$OcrData = F6(
	function (amount, category, note, merchant, date, longNote) {
		return {d: amount, h: category, i: date, r: longNote, k: merchant, m: note};
	});
var $elm$json$Json$Decode$null = _Json_decodeNull;
var $elm$json$Json$Decode$value = _Json_decodeValue;
var $author$project$Json$Decode$Pipeline$optionalDecoder = F3(
	function (path, valDecoder, fallback) {
		var nullOr = function (decoder) {
			return $elm$json$Json$Decode$oneOf(
				_List_fromArray(
					[
						decoder,
						$elm$json$Json$Decode$null(fallback)
					]));
		};
		var handleResult = function (input) {
			var _v0 = A2(
				$elm$json$Json$Decode$decodeValue,
				A2($elm$json$Json$Decode$at, path, $elm$json$Json$Decode$value),
				input);
			if (!_v0.$) {
				var rawValue = _v0.a;
				var _v1 = A2(
					$elm$json$Json$Decode$decodeValue,
					nullOr(valDecoder),
					rawValue);
				if (!_v1.$) {
					var finalResult = _v1.a;
					return $elm$json$Json$Decode$succeed(finalResult);
				} else {
					return A2(
						$elm$json$Json$Decode$at,
						path,
						nullOr(valDecoder));
				}
			} else {
				return $elm$json$Json$Decode$succeed(fallback);
			}
		};
		return A2($elm$json$Json$Decode$andThen, handleResult, $elm$json$Json$Decode$value);
	});
var $author$project$Json$Decode$Pipeline$optional = F4(
	function (key, valDecoder, fallback, decoder) {
		return A2(
			$author$project$Json$Decode$Pipeline$custom,
			A3(
				$author$project$Json$Decode$Pipeline$optionalDecoder,
				_List_fromArray(
					[key]),
				valDecoder,
				fallback),
			decoder);
	});
var $author$project$Main$ocrDataDecoder = A4(
	$author$project$Json$Decode$Pipeline$optional,
	'longNote',
	A2($elm$json$Json$Decode$map, $elm$core$Maybe$Just, $elm$json$Json$Decode$string),
	$elm$core$Maybe$Nothing,
	A4(
		$author$project$Json$Decode$Pipeline$optional,
		'date',
		A2($elm$json$Json$Decode$map, $elm$core$Maybe$Just, $elm$json$Json$Decode$string),
		$elm$core$Maybe$Nothing,
		A4(
			$author$project$Json$Decode$Pipeline$optional,
			'merchant',
			A2($elm$json$Json$Decode$map, $elm$core$Maybe$Just, $elm$json$Json$Decode$string),
			$elm$core$Maybe$Nothing,
			A4(
				$author$project$Json$Decode$Pipeline$optional,
				'note',
				A2($elm$json$Json$Decode$map, $elm$core$Maybe$Just, $elm$json$Json$Decode$string),
				$elm$core$Maybe$Nothing,
				A4(
					$author$project$Json$Decode$Pipeline$optional,
					'category',
					A2(
						$elm$json$Json$Decode$map,
						$elm$core$Maybe$Just,
						A2($elm$json$Json$Decode$map, $author$project$Main$categoryFromString, $elm$json$Json$Decode$string)),
					$elm$core$Maybe$Nothing,
					A4(
						$author$project$Json$Decode$Pipeline$optional,
						'amount',
						A2($elm$json$Json$Decode$map, $elm$core$Maybe$Just, $elm$json$Json$Decode$float),
						$elm$core$Maybe$Nothing,
						$elm$json$Json$Decode$succeed($author$project$Main$OcrData)))))));
var $author$project$Main$monthNum = function (month) {
	switch (month) {
		case 0:
			return 1;
		case 1:
			return 2;
		case 2:
			return 3;
		case 3:
			return 4;
		case 4:
			return 5;
		case 5:
			return 6;
		case 6:
			return 7;
		case 7:
			return 8;
		case 8:
			return 9;
		case 9:
			return 10;
		case 10:
			return 11;
		default:
			return 12;
	}
};
var $elm$core$String$cons = _String_cons;
var $elm$core$String$fromChar = function (_char) {
	return A2($elm$core$String$cons, _char, '');
};
var $elm$core$Bitwise$and = _Bitwise_and;
var $elm$core$Bitwise$shiftRightBy = _Bitwise_shiftRightBy;
var $elm$core$String$repeatHelp = F3(
	function (n, chunk, result) {
		return (n <= 0) ? result : A3(
			$elm$core$String$repeatHelp,
			n >> 1,
			_Utils_ap(chunk, chunk),
			(!(n & 1)) ? result : _Utils_ap(result, chunk));
	});
var $elm$core$String$repeat = F2(
	function (n, chunk) {
		return A3($elm$core$String$repeatHelp, n, chunk, '');
	});
var $elm$core$String$padLeft = F3(
	function (n, _char, string) {
		return _Utils_ap(
			A2(
				$elm$core$String$repeat,
				n - $elm$core$String$length(string),
				$elm$core$String$fromChar(_char)),
			string);
	});
var $elm$time$Time$flooredDiv = F2(
	function (numerator, denominator) {
		return $elm$core$Basics$floor(numerator / denominator);
	});
var $elm$time$Time$posixToMillis = function (_v0) {
	var millis = _v0;
	return millis;
};
var $elm$time$Time$toAdjustedMinutesHelp = F3(
	function (defaultOffset, posixMinutes, eras) {
		toAdjustedMinutesHelp:
		while (true) {
			if (!eras.b) {
				return posixMinutes + defaultOffset;
			} else {
				var era = eras.a;
				var olderEras = eras.b;
				if (_Utils_cmp(era.b1, posixMinutes) < 0) {
					return posixMinutes + era.b;
				} else {
					var $temp$defaultOffset = defaultOffset,
						$temp$posixMinutes = posixMinutes,
						$temp$eras = olderEras;
					defaultOffset = $temp$defaultOffset;
					posixMinutes = $temp$posixMinutes;
					eras = $temp$eras;
					continue toAdjustedMinutesHelp;
				}
			}
		}
	});
var $elm$time$Time$toAdjustedMinutes = F2(
	function (_v0, time) {
		var defaultOffset = _v0.a;
		var eras = _v0.b;
		return A3(
			$elm$time$Time$toAdjustedMinutesHelp,
			defaultOffset,
			A2(
				$elm$time$Time$flooredDiv,
				$elm$time$Time$posixToMillis(time),
				60000),
			eras);
	});
var $elm$core$Basics$ge = _Utils_ge;
var $elm$core$Basics$negate = function (n) {
	return -n;
};
var $elm$time$Time$toCivil = function (minutes) {
	var rawDay = A2($elm$time$Time$flooredDiv, minutes, 60 * 24) + 719468;
	var era = (((rawDay >= 0) ? rawDay : (rawDay - 146096)) / 146097) | 0;
	var dayOfEra = rawDay - (era * 146097);
	var yearOfEra = ((((dayOfEra - ((dayOfEra / 1460) | 0)) + ((dayOfEra / 36524) | 0)) - ((dayOfEra / 146096) | 0)) / 365) | 0;
	var dayOfYear = dayOfEra - (((365 * yearOfEra) + ((yearOfEra / 4) | 0)) - ((yearOfEra / 100) | 0));
	var mp = (((5 * dayOfYear) + 2) / 153) | 0;
	var month = mp + ((mp < 10) ? 3 : (-9));
	var year = yearOfEra + (era * 400);
	return {
		cf: (dayOfYear - ((((153 * mp) + 2) / 5) | 0)) + 1,
		cz: month,
		c5: year + ((month <= 2) ? 1 : 0)
	};
};
var $elm$time$Time$toDay = F2(
	function (zone, time) {
		return $elm$time$Time$toCivil(
			A2($elm$time$Time$toAdjustedMinutes, zone, time)).cf;
	});
var $elm$core$Basics$modBy = _Basics_modBy;
var $elm$time$Time$toHour = F2(
	function (zone, time) {
		return A2(
			$elm$core$Basics$modBy,
			24,
			A2(
				$elm$time$Time$flooredDiv,
				A2($elm$time$Time$toAdjustedMinutes, zone, time),
				60));
	});
var $elm$time$Time$toMinute = F2(
	function (zone, time) {
		return A2(
			$elm$core$Basics$modBy,
			60,
			A2($elm$time$Time$toAdjustedMinutes, zone, time));
	});
var $elm$time$Time$Apr = 3;
var $elm$time$Time$Aug = 7;
var $elm$time$Time$Dec = 11;
var $elm$time$Time$Feb = 1;
var $elm$time$Time$Jan = 0;
var $elm$time$Time$Jul = 6;
var $elm$time$Time$Jun = 5;
var $elm$time$Time$Mar = 2;
var $elm$time$Time$May = 4;
var $elm$time$Time$Nov = 10;
var $elm$time$Time$Oct = 9;
var $elm$time$Time$Sep = 8;
var $elm$time$Time$toMonth = F2(
	function (zone, time) {
		var _v0 = $elm$time$Time$toCivil(
			A2($elm$time$Time$toAdjustedMinutes, zone, time)).cz;
		switch (_v0) {
			case 1:
				return 0;
			case 2:
				return 1;
			case 3:
				return 2;
			case 4:
				return 3;
			case 5:
				return 4;
			case 6:
				return 5;
			case 7:
				return 6;
			case 8:
				return 7;
			case 9:
				return 8;
			case 10:
				return 9;
			case 11:
				return 10;
			default:
				return 11;
		}
	});
var $elm$time$Time$toSecond = F2(
	function (_v0, time) {
		return A2(
			$elm$core$Basics$modBy,
			60,
			A2(
				$elm$time$Time$flooredDiv,
				$elm$time$Time$posixToMillis(time),
				1000));
	});
var $elm$time$Time$toYear = F2(
	function (zone, time) {
		return $elm$time$Time$toCivil(
			A2($elm$time$Time$toAdjustedMinutes, zone, time)).c5;
	});
var $elm$time$Time$utc = A2($elm$time$Time$Zone, 0, _List_Nil);
var $author$project$Main$posixToIso = function (posix) {
	var y = $elm$core$String$fromInt(
		A2($elm$time$Time$toYear, $elm$time$Time$utc, posix));
	var s = A3(
		$elm$core$String$padLeft,
		2,
		'0',
		$elm$core$String$fromInt(
			A2($elm$time$Time$toSecond, $elm$time$Time$utc, posix)));
	var mi = A3(
		$elm$core$String$padLeft,
		2,
		'0',
		$elm$core$String$fromInt(
			A2($elm$time$Time$toMinute, $elm$time$Time$utc, posix)));
	var m = A3(
		$elm$core$String$padLeft,
		2,
		'0',
		$elm$core$String$fromInt(
			$author$project$Main$monthNum(
				A2($elm$time$Time$toMonth, $elm$time$Time$utc, posix))));
	var h = A3(
		$elm$core$String$padLeft,
		2,
		'0',
		$elm$core$String$fromInt(
			A2($elm$time$Time$toHour, $elm$time$Time$utc, posix)));
	var d = A3(
		$elm$core$String$padLeft,
		2,
		'0',
		$elm$core$String$fromInt(
			A2($elm$time$Time$toDay, $elm$time$Time$utc, posix)));
	return y + ('-' + (m + ('-' + (d + ('T' + (h + (':' + (mi + (':' + (s + 'Z'))))))))));
};
var $author$project$Main$requestGeolocation = _Platform_outgoingPort(
	'requestGeolocation',
	function ($) {
		return $elm$json$Json$Encode$null;
	});
var $author$project$Main$saveStorage = _Platform_outgoingPort(
	'saveStorage',
	function ($) {
		return $elm$json$Json$Encode$object(
			_List_fromArray(
				[
					_Utils_Tuple2(
					'key',
					$elm$json$Json$Encode$string($._)),
					_Utils_Tuple2(
					'value',
					$elm$json$Json$Encode$string($.ab))
				]));
	});
var $author$project$Main$setLocation = F2(
	function (ls, p) {
		return _Utils_update(
			p,
			{J: ls});
	});
var $elm$core$List$drop = F2(
	function (n, list) {
		drop:
		while (true) {
			if (n <= 0) {
				return list;
			} else {
				if (!list.b) {
					return list;
				} else {
					var x = list.a;
					var xs = list.b;
					var $temp$n = n - 1,
						$temp$list = xs;
					n = $temp$n;
					list = $temp$list;
					continue drop;
				}
			}
		}
	});
var $elm$core$String$lines = _String_lines;
var $elm$core$String$trim = _String_trim;
var $author$project$Main$stripCodeFence = function (s) {
	var trimmed = $elm$core$String$trim(s);
	return A2($elm$core$String$startsWith, '```', trimmed) ? $elm$core$String$trim(
		A2(
			$elm$core$String$join,
			'\n',
			function (lines) {
				return A2(
					$elm$core$Maybe$withDefault,
					false,
					A2(
						$elm$core$Maybe$map,
						$elm$core$String$startsWith('```'),
						$elm$core$List$head(
							$elm$core$List$reverse(lines)))) ? $elm$core$List$reverse(
					A2(
						$elm$core$List$drop,
						1,
						$elm$core$List$reverse(lines))) : lines;
			}(
				A2(
					$elm$core$List$drop,
					1,
					$elm$core$String$lines(trimmed))))) : trimmed;
};
var $author$project$Main$toGuestState = F2(
	function (reason, as_) {
		return {
			s: {c: as_.c, aI: reason},
			aC: !(!reason),
			K: as_.K,
			ac: as_.ac
		};
	});
var $elm$file$File$toUrl = _File_toUrl;
var $author$project$Main$ToastExpired = {$: 7};
var $elm$core$Process$sleep = _Process_sleep;
var $author$project$Main$toastFor = function (_v0) {
	return A2(
		$elm$core$Task$perform,
		function (_v1) {
			return $author$project$Main$ToastExpired;
		},
		$elm$core$Process$sleep(4000));
};
var $author$project$Main$updateEntry = F3(
	function (creds, sheetId, entry) {
		var range = 'Expenses!A' + ($elm$core$String$fromInt(entry.aK) + (':J' + $elm$core$String$fromInt(entry.aK)));
		var body = $elm$json$Json$Encode$object(
			_List_fromArray(
				[
					_Utils_Tuple2(
					'values',
					A2(
						$elm$json$Json$Encode$list,
						$elm$core$Basics$identity,
						_List_fromArray(
							[
								A2(
								$elm$json$Json$Encode$list,
								$elm$core$Basics$identity,
								_List_fromArray(
									[
										$elm$json$Json$Encode$string(entry.E),
										$elm$json$Json$Encode$string(entry.i),
										$elm$json$Json$Encode$float(entry.d),
										$elm$json$Json$Encode$string(
										$author$project$Main$categoryLabel(entry.h)),
										$elm$json$Json$Encode$string(entry.m),
										$elm$json$Json$Encode$string(entry.k),
										$elm$json$Json$Encode$string(entry.a_),
										A2(
										$elm$core$Maybe$withDefault,
										$elm$json$Json$Encode$string(''),
										A2(
											$elm$core$Maybe$map,
											function (v) {
												return $elm$json$Json$Encode$string(
													$elm$core$String$fromFloat(v));
											},
											entry.M)),
										A2(
										$elm$core$Maybe$withDefault,
										$elm$json$Json$Encode$string(''),
										A2(
											$elm$core$Maybe$map,
											function (v) {
												return $elm$json$Json$Encode$string(
													$elm$core$String$fromFloat(v));
											},
											entry.P)),
										$elm$json$Json$Encode$string(entry.r)
									]))
							])))
				]));
		return $elm$http$Http$request(
			{
				aZ: $elm$http$Http$jsonBody(body),
				a2: $author$project$Main$expectWhateverBody($author$project$Main$EntrySubmitted),
				a4: _List_fromArray(
					[
						A2($elm$http$Http$header, 'Authorization', 'Bearer ' + creds.ap)
					]),
				a7: 'PUT',
				bb: $elm$core$Maybe$Nothing,
				be: $elm$core$Maybe$Nothing,
				bh: 'https://sheets.googleapis.com/v4/spreadsheets/' + (sheetId + ('/values/' + (range + '?valueInputOption=RAW')))
			});
	});
var $author$project$Main$updateScanItem = F2(
	function (id, f) {
		return $elm$core$List$map(
			function (item) {
				return _Utils_eq(item.E, id) ? f(item) : item;
			});
	});
var $author$project$Main$updateAuth = F2(
	function (msg, as_) {
		switch (msg.$) {
			case 0:
				var token = msg.a;
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{
								ag: {ap: token}
							})),
					$author$project$Main$saveStorage(
						{_: 'oauth_token', ab: token}));
			case 3:
				return _Utils_Tuple2(
					$author$project$Main$GuestModel(
						A2($author$project$Main$toGuestState, 0, as_)),
					$author$project$Main$clearStorage(0));
			case 4:
				return _Utils_Tuple2(
					$author$project$Main$GuestModel(
						{
							s: {
								c: {ae: '', az: '', t: '', ax: ''},
								aI: 0
							},
							aC: false,
							K: as_.K,
							ac: as_.ac
						}),
					$author$project$Main$clearAllStorage(0));
			case 8:
				var files = msg.a;
				var startIdx = $elm$core$List$length(as_.n);
				var indexed = A2(
					$elm$core$List$indexedMap,
					F2(
						function (i, f) {
							return _Utils_Tuple2(
								'scan-' + $elm$core$String$fromInt(startIdx + i),
								f);
						}),
					files);
				var newItems = A2(
					$elm$core$List$map,
					function (_v2) {
						var id = _v2.a;
						return $author$project$Main$freshScanItem(id);
					},
					indexed);
				var urlCmds = A2(
					$elm$core$List$map,
					function (_v1) {
						var id = _v1.a;
						var f = _v1.b;
						return A2(
							$elm$core$Task$perform,
							$author$project$Main$GotFileUrl(id),
							$elm$file$File$toUrl(f));
					},
					indexed);
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{
								n: _Utils_ap(as_.n, newItems)
							})),
					$elm$core$Platform$Cmd$batch(urlCmds));
			case 9:
				var itemId = msg.a;
				var dataUrl = msg.b;
				var newStatus = (as_.c.ae !== '') ? 1 : 2;
				var updatedQueue = A3(
					$author$project$Main$updateScanItem,
					itemId,
					function (i) {
						return _Utils_update(
							i,
							{a5: dataUrl, av: newStatus});
					},
					as_.n);
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{n: updatedQueue})),
					$elm$core$Platform$Cmd$batch(
						_List_fromArray(
							[
								(as_.c.ae !== '') ? A4(
								$author$project$Main$makeOcrCall,
								itemId,
								as_.c.ae,
								$author$project$Main$extractBase64(dataUrl),
								$author$project$Main$getMimeType(dataUrl)) : $elm$core$Platform$Cmd$none,
								$author$project$Main$extractExifGps(
								{ce: dataUrl, E: itemId})
							])));
			case 10:
				var itemId = msg.a;
				var result = msg.b;
				var ocrData = function () {
					if (!result.$) {
						var responseBody = result.a;
						var _v4 = A2($elm$json$Json$Decode$decodeString, $author$project$Main$claudeTextDecoder, responseBody);
						if (!_v4.$) {
							var innerJson = _v4.a;
							var _v5 = A2(
								$elm$json$Json$Decode$decodeString,
								$author$project$Main$ocrDataDecoder,
								$author$project$Main$stripCodeFence(innerJson));
							if (!_v5.$) {
								var data = _v5.a;
								return $elm$core$Maybe$Just(data);
							} else {
								return $elm$core$Maybe$Nothing;
							}
						} else {
							return $elm$core$Maybe$Nothing;
						}
					} else {
						return $elm$core$Maybe$Nothing;
					}
				}();
				var updatedQueue = A3(
					$author$project$Main$updateScanItem,
					itemId,
					function (i) {
						return _Utils_update(
							i,
							{a8: ocrData, av: 2});
					},
					as_.n);
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{n: updatedQueue})),
					$elm$core$Platform$Cmd$none);
			case 14:
				var s = msg.a;
				return A2(
					$author$project$Main$authPending,
					function (p) {
						return _Utils_update(
							p,
							{d: s});
					},
					as_);
			case 15:
				var cat = msg.a;
				return A2(
					$author$project$Main$authPending,
					function (p) {
						return _Utils_update(
							p,
							{h: cat});
					},
					as_);
			case 16:
				var s = msg.a;
				return A2(
					$author$project$Main$authPending,
					function (p) {
						return _Utils_update(
							p,
							{m: s});
					},
					as_);
			case 17:
				var s = msg.a;
				return A2(
					$author$project$Main$authPending,
					function (p) {
						return _Utils_update(
							p,
							{r: s});
					},
					as_);
			case 18:
				var s = msg.a;
				return A2(
					$author$project$Main$authPending,
					function (p) {
						return _Utils_update(
							p,
							{k: s});
					},
					as_);
			case 19:
				var s = msg.a;
				return A2(
					$author$project$Main$authPending,
					function (p) {
						return _Utils_update(
							p,
							{i: s});
					},
					as_);
			case 20:
				var _v6 = $elm$core$String$toFloat(as_.l.d);
				if (!_v6.$) {
					return _Utils_Tuple2(
						$author$project$Main$AuthModel(
							_Utils_update(
								as_,
								{ai: $elm$core$Maybe$Nothing, aw: true})),
						A2($elm$core$Task$perform, $author$project$Main$GotSubmitTime, $elm$time$Time$now));
				} else {
					return _Utils_Tuple2(
						$author$project$Main$AuthModel(
							_Utils_update(
								as_,
								{
									ai: $elm$core$Maybe$Just('Enter a valid amount.')
								})),
						$elm$core$Platform$Cmd$none);
				}
			case 21:
				var posix = msg.a;
				var p = as_.l;
				var _v7 = as_.as;
				if (!_v7.$) {
					var original = _v7.a;
					var updated = _Utils_update(
						original,
						{
							d: A2(
								$elm$core$Maybe$withDefault,
								0,
								$elm$core$String$toFloat(p.d)),
							h: p.h,
							i: p.i,
							M: function () {
								var _v8 = p.J;
								switch (_v8.$) {
									case 4:
										var la = _v8.a;
										return $elm$core$Maybe$Just(la);
									case 5:
										return $elm$core$Maybe$Nothing;
									default:
										return original.M;
								}
							}(),
							P: function () {
								var _v9 = p.J;
								switch (_v9.$) {
									case 4:
										var lo = _v9.b;
										return $elm$core$Maybe$Just(lo);
									case 5:
										return $elm$core$Maybe$Nothing;
									default:
										return original.P;
								}
							}(),
							r: p.r,
							k: p.k,
							m: p.m
						});
					return _Utils_Tuple2(
						$author$project$Main$AuthModel(as_),
						A3($author$project$Main$updateEntry, as_.ag, as_.c.t, updated));
				} else {
					var _v10 = function () {
						var _v11 = p.J;
						if (_v11.$ === 4) {
							var la = _v11.a;
							var lo = _v11.b;
							return _Utils_Tuple2(
								$elm$core$Maybe$Just(la),
								$elm$core$Maybe$Just(lo));
						} else {
							return _Utils_Tuple2($elm$core$Maybe$Nothing, $elm$core$Maybe$Nothing);
						}
					}();
					var eLat = _v10.a;
					var eLon = _v10.b;
					var entry = {
						d: A2(
							$elm$core$Maybe$withDefault,
							0,
							$elm$core$String$toFloat(p.d)),
						h: p.h,
						a_: $author$project$Main$posixToIso(posix),
						i: p.i,
						E: 'e-' + $elm$core$String$fromInt(
							$elm$time$Time$posixToMillis(posix)),
						M: eLat,
						P: eLon,
						r: p.r,
						k: p.k,
						m: p.m,
						aK: 0
					};
					return _Utils_Tuple2(
						$author$project$Main$AuthModel(as_),
						A3($author$project$Main$appendEntry, as_.ag, as_.c.t, entry));
				}
			case 22:
				var result = msg.a;
				if (!result.$) {
					var updatedQueue = function () {
						var _v13 = as_.aq;
						if (!_v13.$) {
							var id = _v13.a;
							return A3(
								$author$project$Main$updateScanItem,
								id,
								function (i) {
									return _Utils_update(
										i,
										{av: 3});
								},
								as_.n);
						} else {
							return as_.n;
						}
					}();
					var hasRemaining = A2(
						$elm$core$List$any,
						function (i) {
							return i.av !== 3;
						},
						updatedQueue);
					var nextTab = ((!_Utils_eq(as_.aq, $elm$core$Maybe$Nothing)) && hasRemaining) ? 0 : 2;
					return _Utils_Tuple2(
						$author$project$Main$AuthModel(
							_Utils_update(
								as_,
								{
									aq: $elm$core$Maybe$Nothing,
									as: $elm$core$Maybe$Nothing,
									at: true,
									l: $author$project$Main$defaultPendingEntry(as_.K),
									n: updatedQueue,
									aw: false,
									Y: nextTab
								})),
						A2($author$project$Main$fetchEntries, as_.ag, as_.c.t));
				} else {
					if ((result.a.$ === 3) && (result.a.a === 401)) {
						return _Utils_Tuple2(
							$author$project$Main$GuestModel(
								A2($author$project$Main$toGuestState, 1, as_)),
							$author$project$Main$clearStorage(0));
					} else {
						var e = result.a;
						var toastMsg = 'Save failed: ' + $author$project$Main$httpErrString(e);
						return _Utils_Tuple2(
							$author$project$Main$AuthModel(
								_Utils_update(
									as_,
									{
										aw: false,
										aV: $elm$core$Maybe$Just(toastMsg)
									})),
							$author$project$Main$toastFor(toastMsg));
					}
				}
			case 23:
				var result = msg.a;
				if (!result.$) {
					var entries = result.a;
					return _Utils_Tuple2(
						$author$project$Main$AuthModel(
							_Utils_update(
								as_,
								{U: entries, at: false})),
						$elm$core$Platform$Cmd$none);
				} else {
					if ((result.a.$ === 3) && (result.a.a === 401)) {
						return _Utils_Tuple2(
							$author$project$Main$GuestModel(
								A2($author$project$Main$toGuestState, 1, as_)),
							$author$project$Main$clearStorage(0));
					} else {
						var e = result.a;
						return _Utils_Tuple2(
							$author$project$Main$AuthModel(
								_Utils_update(
									as_,
									{
										ai: $elm$core$Maybe$Just(
											'Load failed: ' + $author$project$Main$httpErrString(e)),
										at: false
									})),
							$elm$core$Platform$Cmd$none);
					}
				}
			case 24:
				var entry = msg.a;
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{
								U: A2(
									$elm$core$List$filter,
									function (e) {
										return !_Utils_eq(e.E, entry.E);
									},
									as_.U)
							})),
					A3($author$project$Main$deleteEntry, as_.ag, as_.c.t, entry.aK));
			case 25:
				var result = msg.a;
				if (!result.$) {
					return _Utils_Tuple2(
						$author$project$Main$AuthModel(as_),
						A2($author$project$Main$fetchEntries, as_.ag, as_.c.t));
				} else {
					if ((result.a.$ === 3) && (result.a.a === 401)) {
						return _Utils_Tuple2(
							$author$project$Main$GuestModel(
								A2($author$project$Main$toGuestState, 1, as_)),
							$author$project$Main$clearStorage(0));
					} else {
						var e = result.a;
						return _Utils_Tuple2(
							$author$project$Main$AuthModel(
								_Utils_update(
									as_,
									{
										ai: $elm$core$Maybe$Just(
											'Delete failed: ' + $author$project$Main$httpErrString(e))
									})),
							$elm$core$Platform$Cmd$none);
					}
				}
			case 26:
				var entry = msg.a;
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{
								as: $elm$core$Maybe$Just(entry),
								ai: $elm$core$Maybe$Nothing,
								l: $author$project$Main$entryToPending(entry),
								Y: 1
							})),
					$elm$core$Platform$Cmd$none);
			case 27:
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{
								as: $elm$core$Maybe$Nothing,
								l: $author$project$Main$defaultPendingEntry(as_.K),
								Y: 2
							})),
					$elm$core$Platform$Cmd$none);
			case 28:
				var tab = msg.a;
				var shouldFetch = (tab === 2) && (as_.c.t !== '');
				var newPending = ((tab === 1) && (!as_.a3)) ? A2($author$project$Main$setLocation, $author$project$Main$LocationFetching, as_.l) : as_.l;
				var geoCmd = ((tab === 1) && (!as_.a3)) ? $author$project$Main$requestGeolocation(0) : $elm$core$Platform$Cmd$none;
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{
								as: (tab !== 1) ? $elm$core$Maybe$Nothing : as_.as,
								at: shouldFetch,
								l: newPending,
								Y: tab
							})),
					$elm$core$Platform$Cmd$batch(
						_List_fromArray(
							[
								shouldFetch ? A2($author$project$Main$fetchEntries, as_.ag, as_.c.t) : $elm$core$Platform$Cmd$none,
								geoCmd
							])));
			case 33:
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{at: true})),
					A2($author$project$Main$fetchEntries, as_.ag, as_.c.t));
			case 29:
				var s = msg.a;
				var cfg = as_.c;
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{
								c: _Utils_update(
									cfg,
									{ae: s})
							})),
					$author$project$Main$saveStorage(
						{_: 'anthropic_key', ab: s}));
			case 30:
				var s = msg.a;
				var cfg = as_.c;
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{
								c: _Utils_update(
									cfg,
									{t: s})
							})),
					$author$project$Main$saveStorage(
						{_: 'sheet_id', ab: s}));
			case 31:
				var s = msg.a;
				var cfg = as_.c;
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{
								c: _Utils_update(
									cfg,
									{az: s})
							})),
					$author$project$Main$saveStorage(
						{_: 'google_client_id', ab: s}));
			case 32:
				var s = msg.a;
				var cfg = as_.c;
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{
								c: _Utils_update(
									cfg,
									{ax: s})
							})),
					$author$project$Main$saveStorage(
						{_: 'trip_start', ab: s}));
			case 34:
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{ai: $elm$core$Maybe$Nothing})),
					$elm$core$Platform$Cmd$none);
			case 35:
				var lat = msg.a;
				var lon = msg.b;
				return A2(
					$author$project$Main$authPending,
					$author$project$Main$setLocation(
						A3($author$project$Main$LocationGot, lat, lon, 1)),
					as_);
			case 36:
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{
								a3: true,
								l: A2($author$project$Main$setLocation, $author$project$Main$LocationIdle, as_.l)
							})),
					$elm$core$Platform$Cmd$none);
			case 37:
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{aL: true})),
					$elm$core$Platform$Cmd$none);
			case 38:
				var lat = msg.a;
				var lon = msg.b;
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{
								l: A2(
									$author$project$Main$setLocation,
									A3($author$project$Main$LocationGot, lat, lon, 2),
									as_.l),
								aL: false
							})),
					$elm$core$Platform$Cmd$none);
			case 39:
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{aL: false})),
					$elm$core$Platform$Cmd$none);
			case 40:
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{
								l: A2($author$project$Main$setLocation, $author$project$Main$LocationSkipped, as_.l),
								aL: false
							})),
					$elm$core$Platform$Cmd$none);
			case 5:
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{aS: !as_.aS})),
					$elm$core$Platform$Cmd$none);
			case 6:
				var message = msg.a;
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{
								aV: $elm$core$Maybe$Just(message)
							})),
					$author$project$Main$toastFor(message));
			case 7:
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{aV: $elm$core$Maybe$Nothing})),
					$elm$core$Platform$Cmd$none);
			case 41:
				if ((!msg.b.$) && (!msg.c.$)) {
					var itemId = msg.a;
					var lat = msg.b.a;
					var lon = msg.c.a;
					return _Utils_Tuple2(
						$author$project$Main$AuthModel(
							_Utils_update(
								as_,
								{
									n: A3(
										$author$project$Main$updateScanItem,
										itemId,
										function (i) {
											return _Utils_update(
												i,
												{
													J: A3($author$project$Main$LocationGot, lat, lon, 0)
												});
										},
										as_.n)
								})),
						$elm$core$Platform$Cmd$none);
				} else {
					var itemId = msg.a;
					var debug = msg.d;
					return _Utils_Tuple2(
						$author$project$Main$AuthModel(
							_Utils_update(
								as_,
								{
									n: A3(
										$author$project$Main$updateScanItem,
										itemId,
										function (i) {
											return _Utils_update(
												i,
												{a1: debug, J: $author$project$Main$LocationNoExifGps});
										},
										as_.n)
								})),
						$elm$core$Platform$Cmd$none);
				}
			case 11:
				var itemId = msg.a;
				var _v16 = $elm$core$List$head(
					A2(
						$elm$core$List$filter,
						function (i) {
							return _Utils_eq(i.E, itemId);
						},
						as_.n));
				if (_v16.$ === 1) {
					return _Utils_Tuple2(
						$author$project$Main$AuthModel(as_),
						$elm$core$Platform$Cmd$none);
				} else {
					var item = _v16.a;
					var ocr = A2(
						$elm$core$Maybe$withDefault,
						{d: $elm$core$Maybe$Nothing, h: $elm$core$Maybe$Nothing, i: $elm$core$Maybe$Nothing, r: $elm$core$Maybe$Nothing, k: $elm$core$Maybe$Nothing, m: $elm$core$Maybe$Nothing},
						item.a8);
					var newPending = {
						d: A2(
							$elm$core$Maybe$withDefault,
							'',
							A2($elm$core$Maybe$map, $elm$core$String$fromFloat, ocr.d)),
						h: A2($elm$core$Maybe$withDefault, 0, ocr.h),
						i: A2($elm$core$Maybe$withDefault, as_.K, ocr.i),
						J: item.J,
						r: A2($elm$core$Maybe$withDefault, '', ocr.r),
						k: A2($elm$core$Maybe$withDefault, '', ocr.k),
						m: A2($elm$core$Maybe$withDefault, '', ocr.m)
					};
					return _Utils_Tuple2(
						$author$project$Main$AuthModel(
							_Utils_update(
								as_,
								{
									aq: $elm$core$Maybe$Just(itemId),
									ai: $elm$core$Maybe$Nothing,
									l: newPending,
									Y: 1
								})),
						$elm$core$Platform$Cmd$none);
				}
			case 12:
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{
								aq: $elm$core$Maybe$Nothing,
								l: $author$project$Main$defaultPendingEntry(as_.K),
								Y: 0
							})),
					$elm$core$Platform$Cmd$none);
			case 13:
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(
						_Utils_update(
							as_,
							{
								n: A2(
									$elm$core$List$filter,
									function (i) {
										return i.av !== 3;
									},
									as_.n)
							})),
					$elm$core$Platform$Cmd$none);
			default:
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(as_),
					$elm$core$Platform$Cmd$none);
		}
	});
var $author$project$Main$MissingConfig = 2;
var $author$project$Main$mapGuestConfig = F2(
	function (f, gs) {
		return _Utils_update(
			gs,
			{
				c: f(gs.c)
			});
	});
var $elm$json$Json$Encode$bool = _Json_wrap;
var $author$project$Main$requestOAuthToken = _Platform_outgoingPort('requestOAuthToken', $elm$json$Json$Encode$bool);
var $author$project$Main$updateGuest = F2(
	function (msg, gs) {
		switch (msg.$) {
			case 1:
				return (gs.s.c.az === '') ? _Utils_Tuple2(
					$author$project$Main$GuestModel(
						_Utils_update(
							gs,
							{
								s: {c: gs.s.c, aI: 2}
							})),
					$elm$core$Platform$Cmd$none) : _Utils_Tuple2(
					$author$project$Main$GuestModel(gs),
					$author$project$Main$requestOAuthToken(true));
			case 0:
				var token = msg.a;
				var as_ = A2(
					$author$project$Main$toAuthState,
					{ap: token},
					gs);
				return _Utils_Tuple2(
					$author$project$Main$AuthModel(as_),
					$elm$core$Platform$Cmd$batch(
						_List_fromArray(
							[
								$author$project$Main$saveStorage(
								{_: 'oauth_token', ab: token}),
								as_.at ? A2(
								$author$project$Main$fetchEntries,
								{ap: token},
								as_.c.t) : $elm$core$Platform$Cmd$none
							])));
			case 2:
				return _Utils_Tuple2(
					$author$project$Main$GuestModel(
						_Utils_update(
							gs,
							{aC: !gs.aC})),
					$elm$core$Platform$Cmd$none);
			case 29:
				var s = msg.a;
				return _Utils_Tuple2(
					$author$project$Main$GuestModel(
						_Utils_update(
							gs,
							{
								s: A2(
									$author$project$Main$mapGuestConfig,
									function (c) {
										return _Utils_update(
											c,
											{ae: s});
									},
									gs.s)
							})),
					$author$project$Main$saveStorage(
						{_: 'anthropic_key', ab: s}));
			case 30:
				var s = msg.a;
				return _Utils_Tuple2(
					$author$project$Main$GuestModel(
						_Utils_update(
							gs,
							{
								s: A2(
									$author$project$Main$mapGuestConfig,
									function (c) {
										return _Utils_update(
											c,
											{t: s});
									},
									gs.s)
							})),
					$author$project$Main$saveStorage(
						{_: 'sheet_id', ab: s}));
			case 31:
				var s = msg.a;
				return _Utils_Tuple2(
					$author$project$Main$GuestModel(
						_Utils_update(
							gs,
							{
								s: A2(
									$author$project$Main$mapGuestConfig,
									function (c) {
										return _Utils_update(
											c,
											{az: s});
									},
									gs.s)
							})),
					$author$project$Main$saveStorage(
						{_: 'google_client_id', ab: s}));
			case 32:
				var s = msg.a;
				return _Utils_Tuple2(
					$author$project$Main$GuestModel(
						_Utils_update(
							gs,
							{
								s: A2(
									$author$project$Main$mapGuestConfig,
									function (c) {
										return _Utils_update(
											c,
											{ax: s});
									},
									gs.s)
							})),
					$author$project$Main$saveStorage(
						{_: 'trip_start', ab: s}));
			case 4:
				var emptyCfg = {ae: '', az: '', t: '', ax: ''};
				return _Utils_Tuple2(
					$author$project$Main$GuestModel(
						_Utils_update(
							gs,
							{
								s: {c: emptyCfg, aI: 0},
								aC: false
							})),
					$author$project$Main$clearAllStorage(0));
			default:
				return _Utils_Tuple2(
					$author$project$Main$GuestModel(gs),
					$elm$core$Platform$Cmd$none);
		}
	});
var $author$project$Main$update = F2(
	function (msg, model) {
		if (!model.$) {
			var gs = model.a;
			return A2($author$project$Main$updateGuest, msg, gs);
		} else {
			var as_ = model.a;
			return A2($author$project$Main$updateAuth, msg, as_);
		}
	});
var $elm$html$Html$div = _VirtualDom_node('div');
var $elm$virtual_dom$VirtualDom$style = _VirtualDom_style;
var $elm$html$Html$Attributes$style = $elm$virtual_dom$VirtualDom$style;
var $author$project$Main$AmountChanged = function (a) {
	return {$: 14, a: a};
};
var $author$project$Main$BackToQueue = {$: 12};
var $author$project$Main$CancelEdit = {$: 27};
var $author$project$Main$DateChanged = function (a) {
	return {$: 19, a: a};
};
var $author$project$Main$LongNoteChanged = function (a) {
	return {$: 17, a: a};
};
var $author$project$Main$MerchantChanged = function (a) {
	return {$: 18, a: a};
};
var $author$project$Main$NoteChanged = function (a) {
	return {$: 16, a: a};
};
var $author$project$Main$SubmitEntry = {$: 20};
var $author$project$Main$allCategories = _List_fromArray(
	[0, 1, 2, 5, 3, 6, 7, 4, 9, 8, 10]);
var $elm$virtual_dom$VirtualDom$attribute = F2(
	function (key, value) {
		return A2(
			_VirtualDom_attribute,
			_VirtualDom_noOnOrFormAction(key),
			_VirtualDom_noJavaScriptOrHtmlUri(value));
	});
var $elm$html$Html$Attributes$attribute = $elm$virtual_dom$VirtualDom$attribute;
var $elm$html$Html$button = _VirtualDom_node('button');
var $elm$html$Html$Attributes$stringProperty = F2(
	function (key, string) {
		return A2(
			_VirtualDom_property,
			key,
			$elm$json$Json$Encode$string(string));
	});
var $elm$html$Html$Attributes$class = $elm$html$Html$Attributes$stringProperty('className');
var $elm$html$Html$Attributes$boolProperty = F2(
	function (key, bool) {
		return A2(
			_VirtualDom_property,
			key,
			$elm$json$Json$Encode$bool(bool));
	});
var $elm$html$Html$Attributes$disabled = $elm$html$Html$Attributes$boolProperty('disabled');
var $elm$virtual_dom$VirtualDom$text = _VirtualDom_text;
var $elm$html$Html$text = $elm$virtual_dom$VirtualDom$text;
var $author$project$Main$formField = F2(
	function (label_, input_) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					A2($elm$html$Html$Attributes$style, 'margin-bottom', '20px')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'font-size', '11px'),
							A2($elm$html$Html$Attributes$style, 'letter-spacing', '0.1em'),
							A2($elm$html$Html$Attributes$style, 'color', '#7a8a80'),
							A2($elm$html$Html$Attributes$style, 'margin-bottom', '8px')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(label_)
						])),
					input_
				]));
	});
var $elm$html$Html$h2 = _VirtualDom_node('h2');
var $elm$html$Html$input = _VirtualDom_node('input');
var $elm$virtual_dom$VirtualDom$Normal = function (a) {
	return {$: 0, a: a};
};
var $elm$virtual_dom$VirtualDom$on = _VirtualDom_on;
var $elm$html$Html$Events$on = F2(
	function (event, decoder) {
		return A2(
			$elm$virtual_dom$VirtualDom$on,
			event,
			$elm$virtual_dom$VirtualDom$Normal(decoder));
	});
var $elm$html$Html$Events$onClick = function (msg) {
	return A2(
		$elm$html$Html$Events$on,
		'click',
		$elm$json$Json$Decode$succeed(msg));
};
var $elm$html$Html$Events$alwaysStop = function (x) {
	return _Utils_Tuple2(x, true);
};
var $elm$virtual_dom$VirtualDom$MayStopPropagation = function (a) {
	return {$: 1, a: a};
};
var $elm$html$Html$Events$stopPropagationOn = F2(
	function (event, decoder) {
		return A2(
			$elm$virtual_dom$VirtualDom$on,
			event,
			$elm$virtual_dom$VirtualDom$MayStopPropagation(decoder));
	});
var $elm$html$Html$Events$targetValue = A2(
	$elm$json$Json$Decode$at,
	_List_fromArray(
		['target', 'value']),
	$elm$json$Json$Decode$string);
var $elm$html$Html$Events$onInput = function (tagger) {
	return A2(
		$elm$html$Html$Events$stopPropagationOn,
		'input',
		A2(
			$elm$json$Json$Decode$map,
			$elm$html$Html$Events$alwaysStop,
			A2($elm$json$Json$Decode$map, tagger, $elm$html$Html$Events$targetValue)));
};
var $elm$html$Html$Attributes$placeholder = $elm$html$Html$Attributes$stringProperty('placeholder');
var $author$project$Main$sectionHead = A2($elm$html$Html$Attributes$style, 'font-size', '13px');
var $elm$html$Html$span = _VirtualDom_node('span');
var $author$project$Main$textInputStyle = A2($elm$html$Html$Attributes$style, 'width', '100%');
var $elm$html$Html$textarea = _VirtualDom_node('textarea');
var $elm$html$Html$Attributes$type_ = $elm$html$Html$Attributes$stringProperty('type');
var $elm$html$Html$Attributes$value = $elm$html$Html$Attributes$stringProperty('value');
var $author$project$Main$CategorySelected = function (a) {
	return {$: 15, a: a};
};
var $author$project$Main$categoryColor = function (cat) {
	switch (cat) {
		case 0:
			return '#e8a020';
		case 1:
			return '#3ecf6a';
		case 2:
			return '#4090e0';
		case 3:
			return '#c060e0';
		case 4:
			return '#e85030';
		case 5:
			return '#40c0b0';
		case 6:
			return '#f0b040';
		case 7:
			return '#e060a0';
		case 8:
			return '#ff6060';
		case 9:
			return '#a0a0e0';
		default:
			return '#7a8a80';
	}
};
var $author$project$Main$categoryIcon = function (cat) {
	switch (cat) {
		case 0:
			return '⛽';
		case 1:
			return '🍔';
		case 2:
			return '⛺';
		case 3:
			return '⛴';
		case 4:
			return '🔧';
		case 5:
			return '🏨';
		case 6:
			return '🎯';
		case 7:
			return '🛍';
		case 8:
			return '💊';
		case 9:
			return '🚌';
		default:
			return '📦';
	}
};
var $author$project$Main$viewCategoryBtn = F2(
	function (selected, cat) {
		var active = _Utils_eq(selected, cat);
		return A2(
			$elm$html$Html$button,
			_List_fromArray(
				[
					$elm$html$Html$Events$onClick(
					$author$project$Main$CategorySelected(cat)),
					A2(
					$elm$html$Html$Attributes$style,
					'background',
					active ? $author$project$Main$categoryColor(cat) : '#1e2220'),
					A2(
					$elm$html$Html$Attributes$style,
					'color',
					active ? '#0d0f0e' : '#c8d0c8'),
					A2(
					$elm$html$Html$Attributes$style,
					'border',
					'1px solid ' + (active ? $author$project$Main$categoryColor(cat) : '#3a4240')),
					A2($elm$html$Html$Attributes$style, 'border-radius', '8px'),
					A2($elm$html$Html$Attributes$style, 'padding', '12px 8px'),
					A2($elm$html$Html$Attributes$style, 'font-size', '14px'),
					A2(
					$elm$html$Html$Attributes$style,
					'font-weight',
					active ? '700' : '400'),
					A2($elm$html$Html$Attributes$style, 'cursor', 'pointer'),
					A2($elm$html$Html$Attributes$style, 'display', 'flex'),
					A2($elm$html$Html$Attributes$style, 'flex-direction', 'column'),
					A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
					A2($elm$html$Html$Attributes$style, 'gap', '4px'),
					A2($elm$html$Html$Attributes$style, 'min-height', '64px')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$span,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'font-size', '20px')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(
							$author$project$Main$categoryIcon(cat))
						])),
					$elm$html$Html$text(
					$author$project$Main$categoryLabel(cat))
				]));
	});
var $author$project$Main$DismissMapPicker = {$: 39};
var $author$project$Main$MapPickerConfirmed = F2(
	function (a, b) {
		return {$: 38, a: a, b: b};
	});
var $elm$virtual_dom$VirtualDom$node = function (tag) {
	return _VirtualDom_node(
		_VirtualDom_noScript(tag));
};
var $elm$html$Html$node = $elm$virtual_dom$VirtualDom$node;
var $author$project$Main$OpenMapPicker = {$: 37};
var $author$project$Main$SkipLocation = {$: 40};
var $author$project$Main$formatCoord = F2(
	function (lat, lon) {
		return A2(
			$elm$core$String$left,
			9,
			$elm$core$String$fromFloat(lat)) + (', ' + A2(
			$elm$core$String$left,
			9,
			$elm$core$String$fromFloat(lon)));
	});
var $author$project$Main$viewLocationStatus = function (ls) {
	switch (ls.$) {
		case 1:
			return A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'color', '#4a5a50'),
						A2($elm$html$Html$Attributes$style, 'font-size', '13px'),
						A2($elm$html$Html$Attributes$style, 'padding', '8px 0')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('📍 Getting location…')
					]));
		case 2:
			return A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('text-[#4a5a50] text-sm py-2')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('📍 Reading photo…')
					]));
		case 3:
			return A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('flex items-center gap-3 py-2')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('text-[#4a5a50] text-sm')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('No GPS in photo')
							])),
						A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Events$onClick($author$project$Main$OpenMapPicker),
								$elm$html$Html$Attributes$class('bg-transparent border-none text-[#4a5a50] text-xs cursor-pointer p-0 font-[inherit]')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('pin manually')
							]))
					]));
		case 4:
			var lat = ls.a;
			var lon = ls.b;
			var source = ls.c;
			var sourceLabel = function () {
				switch (source) {
					case 0:
						return '📍 from photo';
					case 1:
						return '📍 GPS';
					default:
						return '📍 pinned';
				}
			}();
			return A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('flex items-center gap-3 py-2')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('text-[#4090e0] text-sm')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								sourceLabel + (' — ' + A2($author$project$Main$formatCoord, lat, lon)))
							])),
						A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Events$onClick($author$project$Main$OpenMapPicker),
								$elm$html$Html$Attributes$class('bg-transparent border-none text-[#4a5a50] text-xs cursor-pointer p-0 font-[inherit]')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('adjust')
							])),
						A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Events$onClick($author$project$Main$SkipLocation),
								$elm$html$Html$Attributes$class('bg-transparent border-none text-[#4a5a50] text-xs cursor-pointer p-0 font-[inherit]')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('remove')
							]))
					]));
		case 5:
			return A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'display', 'flex'),
						A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
						A2($elm$html$Html$Attributes$style, 'gap', '12px'),
						A2($elm$html$Html$Attributes$style, 'padding', '8px 0')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'color', '#4a5a50'),
								A2($elm$html$Html$Attributes$style, 'font-size', '13px')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('no location')
							])),
						A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Events$onClick($author$project$Main$OpenMapPicker),
								A2($elm$html$Html$Attributes$style, 'background', 'none'),
								A2($elm$html$Html$Attributes$style, 'border', 'none'),
								A2($elm$html$Html$Attributes$style, 'color', '#4a5a50'),
								A2($elm$html$Html$Attributes$style, 'font-size', '12px'),
								A2($elm$html$Html$Attributes$style, 'cursor', 'pointer'),
								A2($elm$html$Html$Attributes$style, 'padding', '0'),
								A2($elm$html$Html$Attributes$style, 'font-family', 'inherit')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('pin manually')
							]))
					]));
		default:
			return A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'display', 'flex'),
						A2($elm$html$Html$Attributes$style, 'gap', '12px'),
						A2($elm$html$Html$Attributes$style, 'align-items', 'center')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Events$onClick($author$project$Main$OpenMapPicker),
								A2($elm$html$Html$Attributes$style, 'background', '#1e2220'),
								A2($elm$html$Html$Attributes$style, 'border', '1px solid #3a4240'),
								A2($elm$html$Html$Attributes$style, 'color', '#c8d0c8'),
								A2($elm$html$Html$Attributes$style, 'border-radius', '8px'),
								A2($elm$html$Html$Attributes$style, 'padding', '12px 16px'),
								A2($elm$html$Html$Attributes$style, 'font-size', '14px'),
								A2($elm$html$Html$Attributes$style, 'cursor', 'pointer'),
								A2($elm$html$Html$Attributes$style, 'flex', '1'),
								A2($elm$html$Html$Attributes$style, 'font-family', 'inherit')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('📍 Pin manually')
							])),
						A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Events$onClick($author$project$Main$SkipLocation),
								A2($elm$html$Html$Attributes$style, 'background', 'none'),
								A2($elm$html$Html$Attributes$style, 'border', 'none'),
								A2($elm$html$Html$Attributes$style, 'color', '#4a5a50'),
								A2($elm$html$Html$Attributes$style, 'font-size', '13px'),
								A2($elm$html$Html$Attributes$style, 'cursor', 'pointer'),
								A2($elm$html$Html$Attributes$style, 'padding', '8px'),
								A2($elm$html$Html$Attributes$style, 'font-family', 'inherit')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('Skip location')
							]))
					]));
	}
};
var $author$project$Main$viewLocationWidget = function (model) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'margin-bottom', '16px')
			]),
		_List_fromArray(
			[
				$author$project$Main$viewLocationStatus(model.l.J),
				model.aL ? A3(
				$elm$html$Html$node,
				'map-picker',
				_List_fromArray(
					[
						A2(
						$elm$html$Html$Attributes$attribute,
						'lat',
						function () {
							var _v0 = model.l.J;
							if (_v0.$ === 4) {
								var la = _v0.a;
								return $elm$core$String$fromFloat(la);
							} else {
								return '64.2008';
							}
						}()),
						A2(
						$elm$html$Html$Attributes$attribute,
						'lon',
						function () {
							var _v1 = model.l.J;
							if (_v1.$ === 4) {
								var lo = _v1.b;
								return $elm$core$String$fromFloat(lo);
							} else {
								return '-153.4937';
							}
						}()),
						A2(
						$elm$html$Html$Events$on,
						'confirm',
						A3(
							$elm$json$Json$Decode$map2,
							$author$project$Main$MapPickerConfirmed,
							A2(
								$elm$json$Json$Decode$at,
								_List_fromArray(
									['detail', 'lat']),
								$elm$json$Json$Decode$float),
							A2(
								$elm$json$Json$Decode$at,
								_List_fromArray(
									['detail', 'lon']),
								$elm$json$Json$Decode$float))),
						A2(
						$elm$html$Html$Events$on,
						'dismiss',
						$elm$json$Json$Decode$succeed($author$project$Main$DismissMapPicker))
					]),
				_List_Nil) : $elm$html$Html$text('')
			]));
};
var $author$project$Main$viewAddTab = function (model) {
	var p = model.l;
	var isEditing = !_Utils_eq(model.as, $elm$core$Maybe$Nothing);
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'padding', '24px 20px')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'display', 'flex'),
						A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
						A2($elm$html$Html$Attributes$style, 'justify-content', 'space-between'),
						A2($elm$html$Html$Attributes$style, 'margin-bottom', '20px')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$h2,
						_List_fromArray(
							[$author$project$Main$sectionHead]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								isEditing ? 'EDIT EXPENSE' : ((!_Utils_eq(model.aq, $elm$core$Maybe$Nothing)) ? 'REVIEW SCAN' : 'ADD EXPENSE'))
							])),
						(!_Utils_eq(model.aq, $elm$core$Maybe$Nothing)) ? A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Events$onClick($author$project$Main$BackToQueue),
								$elm$html$Html$Attributes$class('bg-transparent border-none text-[#7a8a80] text-sm cursor-pointer p-1 font-[inherit]')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('← queue')
							])) : (isEditing ? A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Events$onClick($author$project$Main$CancelEdit),
								$elm$html$Html$Attributes$class('bg-transparent border-none text-[#7a8a80] text-sm cursor-pointer p-1 font-[inherit]')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('← cancel')
							])) : $elm$html$Html$text(''))
					])),
				A2(
				$author$project$Main$formField,
				'AMOUNT',
				A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'position', 'relative')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$span,
							_List_fromArray(
								[
									A2($elm$html$Html$Attributes$style, 'position', 'absolute'),
									A2($elm$html$Html$Attributes$style, 'left', '14px'),
									A2($elm$html$Html$Attributes$style, 'top', '50%'),
									A2($elm$html$Html$Attributes$style, 'transform', 'translateY(-50%)'),
									A2($elm$html$Html$Attributes$style, 'color', '#e8a020'),
									A2($elm$html$Html$Attributes$style, 'font-size', '20px'),
									A2($elm$html$Html$Attributes$style, 'font-family', 'monospace')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('$')
								])),
							A2(
							$elm$html$Html$input,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$type_('number'),
									A2($elm$html$Html$Attributes$attribute, 'inputmode', 'decimal'),
									$elm$html$Html$Attributes$value(p.d),
									$elm$html$Html$Events$onInput($author$project$Main$AmountChanged),
									$elm$html$Html$Attributes$placeholder('0.00'),
									A2($elm$html$Html$Attributes$style, 'width', '100%'),
									A2($elm$html$Html$Attributes$style, 'background', '#1e2220'),
									A2($elm$html$Html$Attributes$style, 'border', '1px solid #3a4240'),
									A2($elm$html$Html$Attributes$style, 'color', '#c8d0c8'),
									A2($elm$html$Html$Attributes$style, 'border-radius', '8px'),
									A2($elm$html$Html$Attributes$style, 'padding', '16px 14px 16px 36px'),
									A2($elm$html$Html$Attributes$style, 'font-size', '24px'),
									A2($elm$html$Html$Attributes$style, 'font-family', 'monospace')
								]),
							_List_Nil)
						]))),
				A2(
				$author$project$Main$formField,
				'CATEGORY',
				A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('grid grid-cols-4 gap-2')
						]),
					A2(
						$elm$core$List$map,
						$author$project$Main$viewCategoryBtn(p.h),
						$author$project$Main$allCategories))),
				A2(
				$author$project$Main$formField,
				'NOTE',
				A2(
					$elm$html$Html$input,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$type_('text'),
							$elm$html$Html$Attributes$value(p.m),
							$elm$html$Html$Events$onInput($author$project$Main$NoteChanged),
							$elm$html$Html$Attributes$placeholder('brief (50 chars)'),
							A2($elm$html$Html$Attributes$attribute, 'maxlength', '50'),
							$author$project$Main$textInputStyle
						]),
					_List_Nil)),
				A2(
				$author$project$Main$formField,
				'DETAILS',
				A2(
					$elm$html$Html$textarea,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$value(p.r),
							$elm$html$Html$Events$onInput($author$project$Main$LongNoteChanged),
							$elm$html$Html$Attributes$placeholder('optional — what happened, where, any context (280 chars)'),
							A2($elm$html$Html$Attributes$attribute, 'maxlength', '280'),
							A2($elm$html$Html$Attributes$attribute, 'rows', '3'),
							$elm$html$Html$Attributes$class('w-full p-3 bg-[#1e2220] border border-[#3a4240] text-[#c8d0c8] rounded-lg font-[inherit] text-base resize-none leading-snug'),
							A2($elm$html$Html$Attributes$style, 'outline', 'none')
						]),
					_List_Nil)),
				A2(
				$author$project$Main$formField,
				'MERCHANT',
				A2(
					$elm$html$Html$input,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$type_('text'),
							$elm$html$Html$Attributes$value(p.k),
							$elm$html$Html$Events$onInput($author$project$Main$MerchantChanged),
							$elm$html$Html$Attributes$placeholder('optional'),
							$author$project$Main$textInputStyle
						]),
					_List_Nil)),
				A2(
				$author$project$Main$formField,
				'DATE',
				A2(
					$elm$html$Html$input,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$type_('date'),
							$elm$html$Html$Attributes$value(p.i),
							$elm$html$Html$Events$onInput($author$project$Main$DateChanged),
							$author$project$Main$textInputStyle
						]),
					_List_Nil)),
				$author$project$Main$viewLocationWidget(model),
				A2(
				$elm$html$Html$button,
				_List_fromArray(
					[
						$elm$html$Html$Events$onClick($author$project$Main$SubmitEntry),
						$elm$html$Html$Attributes$disabled(model.aw),
						A2($elm$html$Html$Attributes$style, 'width', '100%'),
						A2($elm$html$Html$Attributes$style, 'background', '#e8a020'),
						A2($elm$html$Html$Attributes$style, 'color', '#0d0f0e'),
						A2($elm$html$Html$Attributes$style, 'border', 'none'),
						A2($elm$html$Html$Attributes$style, 'border-radius', '8px'),
						A2($elm$html$Html$Attributes$style, 'padding', '18px'),
						A2($elm$html$Html$Attributes$style, 'font-size', '18px'),
						A2($elm$html$Html$Attributes$style, 'font-weight', '700'),
						A2($elm$html$Html$Attributes$style, 'letter-spacing', '0.05em'),
						A2(
						$elm$html$Html$Attributes$style,
						'cursor',
						model.aw ? 'not-allowed' : 'pointer'),
						A2($elm$html$Html$Attributes$style, 'margin-top', '8px'),
						A2($elm$html$Html$Attributes$style, 'min-height', '56px'),
						A2(
						$elm$html$Html$Attributes$style,
						'opacity',
						model.aw ? '0.6' : '1')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(
						model.aw ? 'SAVING...' : (isEditing ? 'UPDATE EXPENSE' : 'SAVE EXPENSE'))
					]))
			]));
};
var $author$project$Main$StatsTab = 3;
var $elm$html$Html$nav = _VirtualDom_node('nav');
var $author$project$Main$TabChanged = function (a) {
	return {$: 28, a: a};
};
var $author$project$Main$viewNavTab = F2(
	function (currentTab, _v0) {
		var tab = _v0.a;
		var icon = _v0.b;
		var label_ = _v0.c;
		var active = _Utils_eq(currentTab, tab);
		return A2(
			$elm$html$Html$button,
			_List_fromArray(
				[
					$elm$html$Html$Events$onClick(
					$author$project$Main$TabChanged(tab)),
					A2($elm$html$Html$Attributes$style, 'flex', '1'),
					A2($elm$html$Html$Attributes$style, 'background', 'none'),
					A2($elm$html$Html$Attributes$style, 'border', 'none'),
					A2($elm$html$Html$Attributes$style, 'padding', '10px 4px'),
					A2($elm$html$Html$Attributes$style, 'display', 'flex'),
					A2($elm$html$Html$Attributes$style, 'flex-direction', 'column'),
					A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
					A2($elm$html$Html$Attributes$style, 'gap', '2px'),
					A2($elm$html$Html$Attributes$style, 'cursor', 'pointer'),
					A2(
					$elm$html$Html$Attributes$style,
					'color',
					active ? '#e8a020' : '#7a8a80'),
					A2($elm$html$Html$Attributes$style, 'min-height', '56px')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$span,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'font-size', '20px')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(icon)
						])),
					A2(
					$elm$html$Html$span,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'font-size', '10px'),
							A2($elm$html$Html$Attributes$style, 'letter-spacing', '0.05em')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(label_)
						]))
				]));
	});
var $author$project$Main$viewBottomNav = function (currentTab) {
	return A2(
		$elm$html$Html$nav,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'position', 'fixed'),
				A2($elm$html$Html$Attributes$style, 'bottom', '0'),
				A2($elm$html$Html$Attributes$style, 'left', '50%'),
				A2($elm$html$Html$Attributes$style, 'transform', 'translateX(-50%)'),
				A2($elm$html$Html$Attributes$style, 'width', '100%'),
				A2($elm$html$Html$Attributes$style, 'max-width', '480px'),
				A2($elm$html$Html$Attributes$style, 'background', '#161918'),
				A2($elm$html$Html$Attributes$style, 'border-top', '1px solid #2a3230'),
				A2($elm$html$Html$Attributes$style, 'display', 'flex'),
				A2($elm$html$Html$Attributes$style, 'z-index', '10')
			]),
		A2(
			$elm$core$List$map,
			$author$project$Main$viewNavTab(currentTab),
			_List_fromArray(
				[
					_Utils_Tuple3(0, '📷', 'Scan'),
					_Utils_Tuple3(1, '+', 'Add'),
					_Utils_Tuple3(2, '☰', 'Ledger'),
					_Utils_Tuple3(3, '▦', 'Stats')
				])));
};
var $author$project$Main$DismissError = {$: 34};
var $author$project$Main$viewErrorBanner = function (maybeErr) {
	if (maybeErr.$ === 1) {
		return $elm$html$Html$text('');
	} else {
		var err = maybeErr.a;
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					A2($elm$html$Html$Attributes$style, 'background', '#2a1510'),
					A2($elm$html$Html$Attributes$style, 'border-left', '4px solid #e85030'),
					A2($elm$html$Html$Attributes$style, 'color', '#e8a020'),
					A2($elm$html$Html$Attributes$style, 'padding', '12px 16px'),
					A2($elm$html$Html$Attributes$style, 'margin', '0 20px 16px'),
					A2($elm$html$Html$Attributes$style, 'border-radius', '0 6px 6px 0'),
					A2($elm$html$Html$Attributes$style, 'font-size', '14px'),
					A2($elm$html$Html$Attributes$style, 'display', 'flex'),
					A2($elm$html$Html$Attributes$style, 'justify-content', 'space-between'),
					A2($elm$html$Html$Attributes$style, 'align-items', 'center')
				]),
			_List_fromArray(
				[
					$elm$html$Html$text(err),
					A2(
					$elm$html$Html$button,
					_List_fromArray(
						[
							$elm$html$Html$Events$onClick($author$project$Main$DismissError),
							A2($elm$html$Html$Attributes$style, 'background', 'none'),
							A2($elm$html$Html$Attributes$style, 'border', 'none'),
							A2($elm$html$Html$Attributes$style, 'color', '#e85030'),
							A2($elm$html$Html$Attributes$style, 'cursor', 'pointer'),
							A2($elm$html$Html$Attributes$style, 'font-size', '18px'),
							A2($elm$html$Html$Attributes$style, 'padding', '0 0 0 12px')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('✕')
						]))
				]));
	}
};
var $author$project$Main$SettingsTab = 4;
var $author$project$Main$viewHeader = function (as_) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'background', '#161918'),
				A2($elm$html$Html$Attributes$style, 'border-bottom', '1px solid #2a3230'),
				A2($elm$html$Html$Attributes$style, 'padding', '12px 20px'),
				A2($elm$html$Html$Attributes$style, 'display', 'flex'),
				A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
				A2($elm$html$Html$Attributes$style, 'justify-content', 'space-between'),
				A2($elm$html$Html$Attributes$style, 'position', 'sticky'),
				A2($elm$html$Html$Attributes$style, 'top', '0'),
				A2($elm$html$Html$Attributes$style, 'z-index', '10')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$span,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'font-size', '18px'),
						A2($elm$html$Html$Attributes$style, 'font-weight', '700'),
						A2($elm$html$Html$Attributes$style, 'color', '#e8a020'),
						A2($elm$html$Html$Attributes$style, 'letter-spacing', '0.08em')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('ALASKA')
					])),
				A2(
				$elm$html$Html$button,
				_List_fromArray(
					[
						$elm$html$Html$Events$onClick(
						(as_.Y === 4) ? $author$project$Main$TabChanged(2) : $author$project$Main$TabChanged(4)),
						A2($elm$html$Html$Attributes$style, 'background', 'none'),
						A2($elm$html$Html$Attributes$style, 'border', 'none'),
						A2($elm$html$Html$Attributes$style, 'font-size', '22px'),
						A2($elm$html$Html$Attributes$style, 'cursor', 'pointer'),
						A2($elm$html$Html$Attributes$style, 'padding', '4px 8px'),
						A2(
						$elm$html$Html$Attributes$style,
						'color',
						(as_.Y === 4) ? '#e8a020' : '#7a8a80')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('⚙')
					]))
			]));
};
var $author$project$Main$RefreshClicked = {$: 33};
var $author$project$Main$ToggleLedgerMap = {$: 5};
var $elm$core$Basics$abs = function (n) {
	return (n < 0) ? (-n) : n;
};
var $elm$core$Basics$round = _Basics_round;
var $author$project$Main$formatAmount = function (amount) {
	var cents = $elm$core$Basics$round(amount * 100);
	var centsRem = $elm$core$Basics$abs(cents) % 100;
	var dollars = (cents / 100) | 0;
	return '$' + ($elm$core$String$fromInt(dollars) + ('.' + A3(
		$elm$core$String$padLeft,
		2,
		'0',
		$elm$core$String$fromInt(centsRem))));
};
var $author$project$Main$formatDateDisplay = function (iso) {
	var _v0 = A2($elm$core$String$split, '-', iso);
	if (((_v0.b && _v0.b.b) && _v0.b.b.b) && (!_v0.b.b.b.b)) {
		var y = _v0.a;
		var _v1 = _v0.b;
		var m = _v1.a;
		var _v2 = _v1.b;
		var d = _v2.a;
		var mn = function () {
			switch (m) {
				case '01':
					return 'Jan';
				case '02':
					return 'Feb';
				case '03':
					return 'Mar';
				case '04':
					return 'Apr';
				case '05':
					return 'May';
				case '06':
					return 'Jun';
				case '07':
					return 'Jul';
				case '08':
					return 'Aug';
				case '09':
					return 'Sep';
				case '10':
					return 'Oct';
				case '11':
					return 'Nov';
				case '12':
					return 'Dec';
				default:
					return m;
			}
		}();
		var day = $elm$core$String$fromInt(
			A2(
				$elm$core$Maybe$withDefault,
				0,
				$elm$core$String$toInt(d)));
		return mn + (' ' + (day + (', ' + y)));
	} else {
		return iso;
	}
};
var $elm$core$List$isEmpty = function (xs) {
	if (!xs.b) {
		return true;
	} else {
		return false;
	}
};
var $elm$virtual_dom$VirtualDom$keyedNode = function (tag) {
	return _VirtualDom_keyedNode(
		_VirtualDom_noScript(tag));
};
var $elm$html$Html$Keyed$node = $elm$virtual_dom$VirtualDom$keyedNode;
var $elm$html$Html$p = _VirtualDom_node('p');
var $elm$core$List$sum = function (numbers) {
	return A3($elm$core$List$foldl, $elm$core$Basics$add, 0, numbers);
};
var $elm$core$String$toUpper = _String_toUpper;
var $elm$core$List$member = F2(
	function (x, xs) {
		return A2(
			$elm$core$List$any,
			function (a) {
				return _Utils_eq(a, x);
			},
			xs);
	});
var $elm$core$List$sortBy = _List_sortBy;
var $elm$core$List$sort = function (xs) {
	return A2($elm$core$List$sortBy, $elm$core$Basics$identity, xs);
};
var $author$project$Main$uniqueDates = function (entries) {
	return $elm$core$List$reverse(
		$elm$core$List$sort(
			A3(
				$elm$core$List$foldr,
				F2(
					function (d, acc) {
						return A2($elm$core$List$member, d, acc) ? acc : A2($elm$core$List$cons, d, acc);
					}),
				_List_Nil,
				A2(
					$elm$core$List$map,
					function ($) {
						return $.i;
					},
					entries))));
};
var $author$project$Main$DeleteEntry = function (a) {
	return {$: 24, a: a};
};
var $author$project$Main$EditEntry = function (a) {
	return {$: 26, a: a};
};
var $elm$html$Html$Attributes$title = $elm$html$Html$Attributes$stringProperty('title');
var $author$project$Main$viewEntryRow = function (entry) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Events$onClick(
				$author$project$Main$EditEntry(entry)),
				A2($elm$html$Html$Attributes$style, 'background', '#161918'),
				A2($elm$html$Html$Attributes$style, 'border-radius', '8px'),
				A2($elm$html$Html$Attributes$style, 'padding', '14px 16px'),
				A2($elm$html$Html$Attributes$style, 'margin-bottom', '8px'),
				A2($elm$html$Html$Attributes$style, 'display', 'flex'),
				A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
				A2($elm$html$Html$Attributes$style, 'gap', '12px'),
				A2($elm$html$Html$Attributes$style, 'cursor', 'pointer')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'width', '10px'),
						A2($elm$html$Html$Attributes$style, 'height', '10px'),
						A2($elm$html$Html$Attributes$style, 'border-radius', '50%'),
						A2(
						$elm$html$Html$Attributes$style,
						'background',
						$author$project$Main$categoryColor(entry.h)),
						A2($elm$html$Html$Attributes$style, 'flex-shrink', '0')
					]),
				_List_Nil),
				A2(
				$elm$html$Html$span,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'font-size', '20px'),
						A2($elm$html$Html$Attributes$style, 'flex-shrink', '0')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(
						$author$project$Main$categoryIcon(entry.h))
					])),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'flex', '1'),
						A2($elm$html$Html$Attributes$style, 'min-width', '0')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'font-size', '15px'),
								A2($elm$html$Html$Attributes$style, 'color', '#c8d0c8'),
								A2($elm$html$Html$Attributes$style, 'white-space', 'nowrap'),
								A2($elm$html$Html$Attributes$style, 'overflow', 'hidden'),
								A2($elm$html$Html$Attributes$style, 'text-overflow', 'ellipsis')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(
								(entry.m !== '') ? entry.m : ((entry.k !== '') ? entry.k : $author$project$Main$categoryLabel(entry.h)))
							])),
						((entry.k !== '') && (entry.m !== '')) ? A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'font-size', '12px'),
								A2($elm$html$Html$Attributes$style, 'color', '#4a5a50')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(entry.k)
							])) : $elm$html$Html$text(''),
						(entry.r !== '') ? A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('text-xs text-[#4a5a50] mt-1 leading-snug line-clamp-2')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(entry.r)
							])) : $elm$html$Html$text('')
					])),
				A2(
				$elm$html$Html$span,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'font-family', 'monospace'),
						A2($elm$html$Html$Attributes$style, 'font-size', '17px'),
						A2($elm$html$Html$Attributes$style, 'color', '#c8d0c8'),
						A2($elm$html$Html$Attributes$style, 'flex-shrink', '0')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(
						$author$project$Main$formatAmount(entry.d))
					])),
				function () {
				var _v0 = entry.M;
				if (!_v0.$) {
					return A2(
						$elm$html$Html$span,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'font-size', '14px'),
								A2($elm$html$Html$Attributes$style, 'color', '#4090e0'),
								A2($elm$html$Html$Attributes$style, 'flex-shrink', '0'),
								$elm$html$Html$Attributes$title('Has GPS coordinates')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('📍')
							]));
				} else {
					return $elm$html$Html$text('');
				}
			}(),
				A2(
				$elm$html$Html$button,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$Events$stopPropagationOn,
						'click',
						$elm$json$Json$Decode$succeed(
							_Utils_Tuple2(
								$author$project$Main$DeleteEntry(entry),
								true))),
						A2($elm$html$Html$Attributes$style, 'background', 'none'),
						A2($elm$html$Html$Attributes$style, 'border', 'none'),
						A2($elm$html$Html$Attributes$style, 'color', '#e85030'),
						A2($elm$html$Html$Attributes$style, 'font-size', '18px'),
						A2($elm$html$Html$Attributes$style, 'cursor', 'pointer'),
						A2($elm$html$Html$Attributes$style, 'padding', '4px 8px'),
						A2($elm$html$Html$Attributes$style, 'flex-shrink', '0'),
						A2($elm$html$Html$Attributes$style, 'min-width', '44px'),
						A2($elm$html$Html$Attributes$style, 'min-height', '44px'),
						A2($elm$html$Html$Attributes$style, 'display', 'flex'),
						A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
						A2($elm$html$Html$Attributes$style, 'justify-content', 'center')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('✕')
					]))
			]));
};
var $author$project$Main$encodeWaypoints = function (entries) {
	var withCoords = A2(
		$elm$core$List$filterMap,
		function (e) {
			var _v0 = _Utils_Tuple2(e.M, e.P);
			if ((!_v0.a.$) && (!_v0.b.$)) {
				var la = _v0.a.a;
				var lo = _v0.b.a;
				return $elm$core$Maybe$Just(
					$elm$json$Json$Encode$object(
						_List_fromArray(
							[
								_Utils_Tuple2(
								'lat',
								$elm$json$Json$Encode$float(la)),
								_Utils_Tuple2(
								'lon',
								$elm$json$Json$Encode$float(lo)),
								_Utils_Tuple2(
								'label',
								$elm$json$Json$Encode$string(
									((e.k !== '') ? e.k : $author$project$Main$categoryLabel(e.h)) + (' ' + $author$project$Main$formatAmount(e.d))))
							])));
			} else {
				return $elm$core$Maybe$Nothing;
			}
		},
		entries);
	return A2(
		$elm$json$Json$Encode$encode,
		0,
		A2($elm$json$Json$Encode$list, $elm$core$Basics$identity, withCoords));
};
var $author$project$Main$viewLedgerMap = function (model) {
	return model.aS ? A3(
		$elm$html$Html$node,
		'waypoint-map',
		_List_fromArray(
			[
				A2(
				$elm$html$Html$Attributes$attribute,
				'points',
				$author$project$Main$encodeWaypoints(model.U)),
				$elm$html$Html$Attributes$class('block w-full rounded-xl overflow-hidden mb-5'),
				A2($elm$html$Html$Attributes$style, 'height', '260px')
			]),
		_List_Nil) : $elm$html$Html$text('');
};
var $author$project$Main$viewLedgerSummary = function (entries) {
	var total = $elm$core$List$sum(
		A2(
			$elm$core$List$map,
			function ($) {
				return $.d;
			},
			entries));
	var catRow = A2(
		$elm$core$List$filterMap,
		function (cat) {
			var t = $elm$core$List$sum(
				A2(
					$elm$core$List$map,
					function ($) {
						return $.d;
					},
					A2(
						$elm$core$List$filter,
						function (e) {
							return _Utils_eq(e.h, cat);
						},
						entries)));
			return (t > 0) ? $elm$core$Maybe$Just(
				_Utils_Tuple2(cat, t)) : $elm$core$Maybe$Nothing;
		},
		$author$project$Main$allCategories);
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'background', '#161918'),
				A2($elm$html$Html$Attributes$style, 'border-radius', '10px'),
				A2($elm$html$Html$Attributes$style, 'padding', '14px 16px'),
				A2($elm$html$Html$Attributes$style, 'margin-bottom', '20px')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'font-family', 'monospace'),
						A2($elm$html$Html$Attributes$style, 'font-size', '22px'),
						A2($elm$html$Html$Attributes$style, 'color', '#e8a020'),
						A2($elm$html$Html$Attributes$style, 'margin-bottom', '12px')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text(
						$author$project$Main$formatAmount(total))
					])),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'display', 'flex'),
						A2($elm$html$Html$Attributes$style, 'flex-wrap', 'wrap'),
						A2($elm$html$Html$Attributes$style, 'gap', '10px')
					]),
				A2(
					$elm$core$List$map,
					function (_v0) {
						var cat = _v0.a;
						var t = _v0.b;
						return A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									A2($elm$html$Html$Attributes$style, 'display', 'flex'),
									A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
									A2($elm$html$Html$Attributes$style, 'gap', '4px')
								]),
							_List_fromArray(
								[
									A2(
									$elm$html$Html$span,
									_List_fromArray(
										[
											A2($elm$html$Html$Attributes$style, 'font-size', '15px')
										]),
									_List_fromArray(
										[
											$elm$html$Html$text(
											$author$project$Main$categoryIcon(cat))
										])),
									A2(
									$elm$html$Html$span,
									_List_fromArray(
										[
											A2($elm$html$Html$Attributes$style, 'font-family', 'monospace'),
											A2($elm$html$Html$Attributes$style, 'font-size', '13px'),
											A2($elm$html$Html$Attributes$style, 'color', '#7a8a80')
										]),
									_List_fromArray(
										[
											$elm$html$Html$text(
											$author$project$Main$formatAmount(t))
										]))
								]));
					},
					catRow))
			]));
};
var $elm$core$List$repeatHelp = F3(
	function (result, n, value) {
		repeatHelp:
		while (true) {
			if (n <= 0) {
				return result;
			} else {
				var $temp$result = A2($elm$core$List$cons, value, result),
					$temp$n = n - 1,
					$temp$value = value;
				result = $temp$result;
				n = $temp$n;
				value = $temp$value;
				continue repeatHelp;
			}
		}
	});
var $elm$core$List$repeat = F2(
	function (n, value) {
		return A3($elm$core$List$repeatHelp, _List_Nil, n, value);
	});
var $author$project$Main$viewSkeleton = A2(
	$elm$html$Html$div,
	_List_Nil,
	A2(
		$elm$core$List$repeat,
		5,
		A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					A2($elm$html$Html$Attributes$style, 'background', '#161918'),
					A2($elm$html$Html$Attributes$style, 'border-radius', '8px'),
					A2($elm$html$Html$Attributes$style, 'padding', '18px 16px'),
					A2($elm$html$Html$Attributes$style, 'margin-bottom', '8px'),
					A2($elm$html$Html$Attributes$style, 'display', 'flex'),
					A2($elm$html$Html$Attributes$style, 'gap', '12px')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'width', '10px'),
							A2($elm$html$Html$Attributes$style, 'height', '10px'),
							A2($elm$html$Html$Attributes$style, 'border-radius', '50%'),
							A2($elm$html$Html$Attributes$style, 'background', '#2a3230')
						]),
					_List_Nil),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'flex', '1'),
							A2($elm$html$Html$Attributes$style, 'height', '16px'),
							A2($elm$html$Html$Attributes$style, 'background', '#2a3230'),
							A2($elm$html$Html$Attributes$style, 'border-radius', '4px')
						]),
					_List_Nil),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'width', '60px'),
							A2($elm$html$Html$Attributes$style, 'height', '16px'),
							A2($elm$html$Html$Attributes$style, 'background', '#2a3230'),
							A2($elm$html$Html$Attributes$style, 'border-radius', '4px')
						]),
					_List_Nil)
				]))));
var $author$project$Main$viewLedgerTab = function (model) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'padding', '20px')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('flex items-center justify-between mb-5')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$h2,
						_List_fromArray(
							[$author$project$Main$sectionHead]),
						_List_fromArray(
							[
								$elm$html$Html$text('LEDGER')
							])),
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('flex gap-2')
							]),
						_List_fromArray(
							[
								A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Events$onClick($author$project$Main$ToggleLedgerMap),
										$elm$html$Html$Attributes$class(
										model.aS ? 'px-3 py-1.5 rounded border border-[#3a4240] bg-[#1e3a50] text-[#4090e0] text-sm cursor-pointer font-[inherit]' : 'px-3 py-1.5 rounded border border-[#3a4240] bg-transparent text-[#7a8a80] text-sm cursor-pointer font-[inherit]')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('🗺 map')
									])),
								A2(
								$elm$html$Html$button,
								_List_fromArray(
									[
										$elm$html$Html$Events$onClick($author$project$Main$RefreshClicked),
										$elm$html$Html$Attributes$class('px-3 py-1.5 rounded border border-[#3a4240] bg-transparent text-[#7a8a80] text-sm cursor-pointer font-[inherit]')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('↻ refresh')
									]))
							]))
					])),
				(!$elm$core$List$isEmpty(model.U)) ? $author$project$Main$viewLedgerSummary(model.U) : $elm$html$Html$text(''),
				$author$project$Main$viewLedgerMap(model),
				(model.c.t === '') ? A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'color', '#7a8a80'),
						A2($elm$html$Html$Attributes$style, 'text-align', 'center'),
						A2($elm$html$Html$Attributes$style, 'padding', '32px 0')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('Enter your Sheet ID in Settings to get started.')
					])) : (model.at ? $author$project$Main$viewSkeleton : ($elm$core$List$isEmpty(model.U) ? A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'color', '#7a8a80'),
						A2($elm$html$Html$Attributes$style, 'text-align', 'center'),
						A2($elm$html$Html$Attributes$style, 'padding', '32px 0')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('No expenses yet. Add your first one!')
					])) : A3(
				$elm$html$Html$Keyed$node,
				'div',
				_List_Nil,
				A2(
					$elm$core$List$map,
					function (date) {
						var dayEntries = A2(
							$elm$core$List$filter,
							function (e) {
								return _Utils_eq(e.i, date);
							},
							model.U);
						return _Utils_Tuple2(
							date,
							A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										A2($elm$html$Html$Attributes$style, 'margin-bottom', '24px')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												A2($elm$html$Html$Attributes$style, 'font-size', '11px'),
												A2($elm$html$Html$Attributes$style, 'letter-spacing', '0.1em'),
												A2($elm$html$Html$Attributes$style, 'color', '#7a8a80'),
												A2($elm$html$Html$Attributes$style, 'margin-bottom', '8px'),
												A2($elm$html$Html$Attributes$style, 'padding-bottom', '6px'),
												A2($elm$html$Html$Attributes$style, 'border-bottom', '1px solid #2a3230'),
												A2($elm$html$Html$Attributes$style, 'display', 'flex'),
												A2($elm$html$Html$Attributes$style, 'justify-content', 'space-between'),
												A2($elm$html$Html$Attributes$style, 'align-items', 'center')
											]),
										_List_fromArray(
											[
												$elm$html$Html$text(
												$elm$core$String$toUpper(
													$author$project$Main$formatDateDisplay(date))),
												A2(
												$elm$html$Html$span,
												_List_fromArray(
													[
														A2($elm$html$Html$Attributes$style, 'font-family', 'monospace'),
														A2($elm$html$Html$Attributes$style, 'color', '#e8a020'),
														A2($elm$html$Html$Attributes$style, 'letter-spacing', '0')
													]),
												_List_fromArray(
													[
														$elm$html$Html$text(
														$author$project$Main$formatAmount(
															$elm$core$List$sum(
																A2(
																	$elm$core$List$map,
																	function ($) {
																		return $.d;
																	},
																	dayEntries))))
													]))
											])),
										A3(
										$elm$html$Html$Keyed$node,
										'div',
										_List_Nil,
										A2(
											$elm$core$List$map,
											function (e) {
												return _Utils_Tuple2(
													e.E,
													$author$project$Main$viewEntryRow(e));
											},
											dayEntries))
									])));
					},
					$author$project$Main$uniqueDates(model.U)))))
			]));
};
var $author$project$Main$ClearDoneItems = {$: 13};
var $author$project$Main$FilesSelected = function (a) {
	return {$: 8, a: a};
};
var $elm$html$Html$Attributes$accept = $elm$html$Html$Attributes$stringProperty('accept');
var $elm$file$File$decoder = _File_decoder;
var $elm$json$Json$Decode$int = _Json_decodeInt;
var $author$project$Main$fileListDecoder = A2(
	$elm$json$Json$Decode$andThen,
	function (n) {
		return A3(
			$elm$core$List$foldr,
			$elm$json$Json$Decode$map2($elm$core$List$cons),
			$elm$json$Json$Decode$succeed(_List_Nil),
			A2(
				$elm$core$List$map,
				function (i) {
					return A2(
						$elm$json$Json$Decode$field,
						$elm$core$String$fromInt(i),
						$elm$file$File$decoder);
				},
				A2($elm$core$List$range, 0, n - 1)));
	},
	A2($elm$json$Json$Decode$field, 'length', $elm$json$Json$Decode$int));
var $elm$html$Html$label = _VirtualDom_node('label');
var $elm$html$Html$img = _VirtualDom_node('img');
var $elm$html$Html$Attributes$src = function (url) {
	return A2(
		$elm$html$Html$Attributes$stringProperty,
		'src',
		_VirtualDom_noJavaScriptOrHtmlUri(url));
};
var $author$project$Main$ReviewScanItem = function (a) {
	return {$: 11, a: a};
};
var $author$project$Main$viewScanCardStatus = function (item) {
	var _v0 = item.av;
	switch (_v0) {
		case 0:
			return A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('text-[#4a5a50] text-xs py-1')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('Queued…')
					]));
		case 1:
			return A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('text-[#e8a020] text-xs py-1')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('⏳ Reading…')
					]));
		case 2:
			return A2(
				$elm$html$Html$div,
				_List_Nil,
				_List_fromArray(
					[
						function () {
						var _v1 = item.a8;
						if (!_v1.$) {
							var ocr = _v1.a;
							return A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('mb-2')
									]),
								_List_fromArray(
									[
										A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('text-[#e8a020] font-mono text-sm font-bold')
											]),
										_List_fromArray(
											[
												$elm$html$Html$text(
												A2(
													$elm$core$Maybe$withDefault,
													'—',
													A2(
														$elm$core$Maybe$map,
														function (a) {
															return '$' + $elm$core$String$fromFloat(a);
														},
														ocr.d)))
											])),
										A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												$elm$html$Html$Attributes$class('text-[#7a8a80] text-xs truncate')
											]),
										_List_fromArray(
											[
												$elm$html$Html$text(
												A2(
													$elm$core$Maybe$withDefault,
													A2(
														$elm$core$Maybe$withDefault,
														'receipt',
														A2($elm$core$Maybe$map, $author$project$Main$categoryLabel, ocr.h)),
													ocr.k))
											]))
									]));
						} else {
							return A2(
								$elm$html$Html$div,
								_List_fromArray(
									[
										$elm$html$Html$Attributes$class('text-[#7a8a80] text-xs mb-2')
									]),
								_List_fromArray(
									[
										$elm$html$Html$text('Fill manually')
									]));
						}
					}(),
						A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Events$onClick(
								$author$project$Main$ReviewScanItem(item.E)),
								$elm$html$Html$Attributes$class('w-full py-1.5 rounded-lg bg-[#e8a020] text-[#0d0f0e] text-xs font-bold cursor-pointer border-none font-[inherit]')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('Review →')
							]))
					]));
		default:
			return A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('text-[#4a5a50] text-xs text-center py-1')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('✓ Submitted')
					]));
	}
};
var $author$project$Main$viewScanCard = function (item) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('bg-[#161918] rounded-xl overflow-hidden')
			]),
		_List_fromArray(
			[
				(item.a5 !== '') ? A2(
				$elm$html$Html$img,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$src(item.a5),
						$elm$html$Html$Attributes$class('w-full h-28 object-cover')
					]),
				_List_Nil) : A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('w-full h-28 bg-[#1e2220] flex items-center justify-center text-3xl text-[#3a4240]')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('📷')
					])),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('p-2')
					]),
				_List_fromArray(
					[
						$author$project$Main$viewScanCardStatus(item)
					]))
			]));
};
var $author$project$Main$viewScanTab = function (model) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				$elm$html$Html$Attributes$class('px-5 pt-6 pb-4')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$h2,
				_List_fromArray(
					[$author$project$Main$sectionHead]),
				_List_fromArray(
					[
						$elm$html$Html$text('SCAN RECEIPTS')
					])),
				A2(
				$elm$html$Html$label,
				_List_fromArray(
					[
						$elm$html$Html$Attributes$class('flex flex-col items-center justify-center bg-[#1e2220] border-2 border-dashed border-[#3a4240] rounded-xl py-10 px-6 cursor-pointer mb-5')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('text-5xl mb-3')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('📷')
							])),
						A2(
						$elm$html$Html$p,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('text-[#7a8a80] text-base text-center')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('Tap to add photos')
							])),
						A2(
						$elm$html$Html$p,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('text-[#4a5a50] text-xs mt-1 text-center')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('Select multiple for batch upload')
							])),
						A2(
						$elm$html$Html$input,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$type_('file'),
								$elm$html$Html$Attributes$accept('image/*'),
								A2($elm$html$Html$Attributes$attribute, 'multiple', 'true'),
								$elm$html$Html$Attributes$class('hidden'),
								A2(
								$elm$html$Html$Events$on,
								'change',
								A2(
									$elm$json$Json$Decode$map,
									$author$project$Main$FilesSelected,
									A2(
										$elm$json$Json$Decode$at,
										_List_fromArray(
											['target', 'files']),
										$author$project$Main$fileListDecoder)))
							]),
						_List_Nil)
					])),
				$elm$core$List$isEmpty(model.n) ? A2(
				$elm$html$Html$button,
				_List_fromArray(
					[
						$elm$html$Html$Events$onClick(
						$author$project$Main$TabChanged(1)),
						$elm$html$Html$Attributes$class('w-full py-3.5 rounded-lg border border-[#3a4240] text-[#7a8a80] text-sm cursor-pointer bg-transparent font-[inherit]')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('Fill in manually →')
					])) : A2(
				$elm$html$Html$div,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('grid grid-cols-2 gap-3 mb-4')
							]),
						A2($elm$core$List$map, $author$project$Main$viewScanCard, model.n)),
						A2(
						$elm$core$List$any,
						function (i) {
							return i.av === 3;
						},
						model.n) ? A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Events$onClick($author$project$Main$ClearDoneItems),
								$elm$html$Html$Attributes$class('w-full py-2 rounded-lg border border-[#3a4240] text-[#4a5a50] text-xs cursor-pointer bg-transparent font-[inherit] mb-4')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('Clear submitted')
							])) : $elm$html$Html$text(''),
						function () {
						var debugItems = A2(
							$elm$core$List$filter,
							function (i) {
								return i.a1 !== '';
							},
							model.n);
						return $elm$core$List$isEmpty(debugItems) ? $elm$html$Html$text('') : A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									$elm$html$Html$Attributes$class('mt-2')
								]),
							A2(
								$elm$core$List$indexedMap,
								F2(
									function (idx, item) {
										return A2(
											$elm$html$Html$div,
											_List_fromArray(
												[
													$elm$html$Html$Attributes$class('mb-3 rounded-lg bg-[#161918] p-3')
												]),
											_List_fromArray(
												[
													A2(
													$elm$html$Html$div,
													_List_fromArray(
														[
															$elm$html$Html$Attributes$class('text-[#4a5a50] text-xs mb-1')
														]),
													_List_fromArray(
														[
															$elm$html$Html$text(
															'EXIF dump — photo ' + $elm$core$String$fromInt(idx + 1))
														])),
													A2(
													$elm$html$Html$div,
													_List_fromArray(
														[
															$elm$html$Html$Attributes$class('font-mono text-[10px] text-[#7a8a80] break-all whitespace-pre-wrap max-h-40 overflow-y-auto')
														]),
													_List_fromArray(
														[
															$elm$html$Html$text(item.a1)
														]))
												]));
									}),
								debugItems));
					}()
					]))
			]));
};
var $author$project$Main$ApiKeyChanged = function (a) {
	return {$: 29, a: a};
};
var $author$project$Main$GoogleClientIdChanged = function (a) {
	return {$: 31, a: a};
};
var $author$project$Main$ResetSettingsClicked = {$: 4};
var $author$project$Main$SheetIdChanged = function (a) {
	return {$: 30, a: a};
};
var $author$project$Main$SignOutClicked = {$: 3};
var $author$project$Main$TripStartChanged = function (a) {
	return {$: 32, a: a};
};
var $author$project$Main$viewSettingsPanel = F3(
	function (cfg, isSignedIn, version) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					A2($elm$html$Html$Attributes$style, 'padding', '24px 20px')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$h2,
					_List_fromArray(
						[$author$project$Main$sectionHead]),
					_List_fromArray(
						[
							$elm$html$Html$text('SETTINGS')
						])),
					A2(
					$author$project$Main$formField,
					'GOOGLE CLIENT ID',
					A2(
						$elm$html$Html$input,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$type_('text'),
								$elm$html$Html$Attributes$value(cfg.az),
								$elm$html$Html$Events$onInput($author$project$Main$GoogleClientIdChanged),
								$elm$html$Html$Attributes$placeholder('123456789-abc...apps.googleusercontent.com'),
								$author$project$Main$textInputStyle
							]),
						_List_Nil)),
					A2(
					$author$project$Main$formField,
					'GOOGLE SHEET ID',
					A2(
						$elm$html$Html$input,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$type_('text'),
								$elm$html$Html$Attributes$value(cfg.t),
								$elm$html$Html$Events$onInput($author$project$Main$SheetIdChanged),
								$elm$html$Html$Attributes$placeholder('1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms'),
								$author$project$Main$textInputStyle
							]),
						_List_Nil)),
					A2(
					$author$project$Main$formField,
					'ANTHROPIC API KEY',
					A2(
						$elm$html$Html$input,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$type_('password'),
								$elm$html$Html$Attributes$value(cfg.ae),
								$elm$html$Html$Events$onInput($author$project$Main$ApiKeyChanged),
								$elm$html$Html$Attributes$placeholder('sk-ant-...'),
								$author$project$Main$textInputStyle
							]),
						_List_Nil)),
					A2(
					$author$project$Main$formField,
					'TRIP START DATE',
					A2(
						$elm$html$Html$input,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$type_('date'),
								$elm$html$Html$Attributes$value(cfg.ax),
								$elm$html$Html$Events$onInput($author$project$Main$TripStartChanged),
								$author$project$Main$textInputStyle
							]),
						_List_Nil)),
					isSignedIn ? A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'margin-top', '32px')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$button,
							_List_fromArray(
								[
									$elm$html$Html$Events$onClick($author$project$Main$SignOutClicked),
									A2($elm$html$Html$Attributes$style, 'width', '100%'),
									A2($elm$html$Html$Attributes$style, 'background', 'none'),
									A2($elm$html$Html$Attributes$style, 'border', '1px solid #e85030'),
									A2($elm$html$Html$Attributes$style, 'color', '#e85030'),
									A2($elm$html$Html$Attributes$style, 'border-radius', '8px'),
									A2($elm$html$Html$Attributes$style, 'padding', '14px'),
									A2($elm$html$Html$Attributes$style, 'font-size', '15px'),
									A2($elm$html$Html$Attributes$style, 'cursor', 'pointer')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('SIGN OUT')
								]))
						])) : $elm$html$Html$text(''),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'margin-top', '8px')
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$button,
							_List_fromArray(
								[
									$elm$html$Html$Events$onClick($author$project$Main$ResetSettingsClicked),
									$elm$html$Html$Attributes$class('w-full py-3.5 rounded-lg border border-red-900/60 text-red-400/80 text-sm cursor-pointer bg-transparent font-[inherit] hover:border-red-700 hover:text-red-300 transition-colors')
								]),
							_List_fromArray(
								[
									$elm$html$Html$text('Reset all settings')
								]))
						])),
					(version !== '') ? A2(
					$elm$html$Html$p,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('text-[#3a4a40] text-xs text-center mt-6 font-mono')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(version)
						])) : $elm$html$Html$text('')
				]));
	});
var $elm$core$Basics$composeL = F3(
	function (g, f, x) {
		return g(
			f(x));
	});
var $elm$core$Tuple$second = function (_v0) {
	var y = _v0.b;
	return y;
};
var $author$project$Main$biggestDay = function (entries) {
	return $elm$core$List$head(
		A2(
			$elm$core$List$sortBy,
			A2($elm$core$Basics$composeL, $elm$core$Basics$negate, $elm$core$Tuple$second),
			A2(
				$elm$core$List$map,
				function (date) {
					return _Utils_Tuple2(
						date,
						$elm$core$List$sum(
							A2(
								$elm$core$List$map,
								function ($) {
									return $.d;
								},
								A2(
									$elm$core$List$filter,
									function (e) {
										return _Utils_eq(e.i, date);
									},
									entries))));
				},
				$author$project$Main$uniqueDates(entries))));
};
var $author$project$Main$isoToDayCount = function (s) {
	var _v0 = A2(
		$elm$core$List$filterMap,
		$elm$core$String$toInt,
		A2($elm$core$String$split, '-', s));
	if (((_v0.b && _v0.b.b) && _v0.b.b.b) && (!_v0.b.b.b.b)) {
		var y = _v0.a;
		var _v1 = _v0.b;
		var m = _v1.a;
		var _v2 = _v1.b;
		var d = _v2.a;
		var monthOffsets = _List_fromArray(
			[0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]);
		var offset = A2(
			$elm$core$Maybe$withDefault,
			0,
			$elm$core$List$head(
				A2($elm$core$List$drop, m - 1, monthOffsets)));
		return ((y * 365) + offset) + d;
	} else {
		return 0;
	}
};
var $author$project$Main$medianAmount = function (entries) {
	var amounts = $elm$core$List$sort(
		A2(
			$elm$core$List$map,
			function ($) {
				return $.d;
			},
			entries));
	var n = $elm$core$List$length(amounts);
	var mid = (n / 2) | 0;
	if (!n) {
		return 0;
	} else {
		if ((n % 2) === 1) {
			return A2(
				$elm$core$Maybe$withDefault,
				0,
				$elm$core$List$head(
					A2($elm$core$List$drop, mid, amounts)));
		} else {
			var b = A2(
				$elm$core$Maybe$withDefault,
				0,
				$elm$core$List$head(
					A2($elm$core$List$drop, mid, amounts)));
			var a = A2(
				$elm$core$Maybe$withDefault,
				0,
				$elm$core$List$head(
					A2($elm$core$List$drop, mid - 1, amounts)));
			return (a + b) / 2;
		}
	}
};
var $author$project$Main$statCard = F2(
	function (label_, value) {
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					A2($elm$html$Html$Attributes$style, 'background', '#161918'),
					A2($elm$html$Html$Attributes$style, 'border-radius', '10px'),
					A2($elm$html$Html$Attributes$style, 'padding', '16px')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'font-size', '11px'),
							A2($elm$html$Html$Attributes$style, 'letter-spacing', '0.1em'),
							A2($elm$html$Html$Attributes$style, 'color', '#7a8a80'),
							A2($elm$html$Html$Attributes$style, 'margin-bottom', '6px')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(label_)
						])),
					A2(
					$elm$html$Html$div,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'font-size', '22px'),
							A2($elm$html$Html$Attributes$style, 'font-family', 'monospace'),
							A2($elm$html$Html$Attributes$style, 'color', '#e8a020')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(value)
						]))
				]));
	});
var $elm$core$List$takeReverse = F3(
	function (n, list, kept) {
		takeReverse:
		while (true) {
			if (n <= 0) {
				return kept;
			} else {
				if (!list.b) {
					return kept;
				} else {
					var x = list.a;
					var xs = list.b;
					var $temp$n = n - 1,
						$temp$list = xs,
						$temp$kept = A2($elm$core$List$cons, x, kept);
					n = $temp$n;
					list = $temp$list;
					kept = $temp$kept;
					continue takeReverse;
				}
			}
		}
	});
var $elm$core$List$takeTailRec = F2(
	function (n, list) {
		return $elm$core$List$reverse(
			A3($elm$core$List$takeReverse, n, list, _List_Nil));
	});
var $elm$core$List$takeFast = F3(
	function (ctr, n, list) {
		if (n <= 0) {
			return _List_Nil;
		} else {
			var _v0 = _Utils_Tuple2(n, list);
			_v0$1:
			while (true) {
				_v0$5:
				while (true) {
					if (!_v0.b.b) {
						return list;
					} else {
						if (_v0.b.b.b) {
							switch (_v0.a) {
								case 1:
									break _v0$1;
								case 2:
									var _v2 = _v0.b;
									var x = _v2.a;
									var _v3 = _v2.b;
									var y = _v3.a;
									return _List_fromArray(
										[x, y]);
								case 3:
									if (_v0.b.b.b.b) {
										var _v4 = _v0.b;
										var x = _v4.a;
										var _v5 = _v4.b;
										var y = _v5.a;
										var _v6 = _v5.b;
										var z = _v6.a;
										return _List_fromArray(
											[x, y, z]);
									} else {
										break _v0$5;
									}
								default:
									if (_v0.b.b.b.b && _v0.b.b.b.b.b) {
										var _v7 = _v0.b;
										var x = _v7.a;
										var _v8 = _v7.b;
										var y = _v8.a;
										var _v9 = _v8.b;
										var z = _v9.a;
										var _v10 = _v9.b;
										var w = _v10.a;
										var tl = _v10.b;
										return (ctr > 1000) ? A2(
											$elm$core$List$cons,
											x,
											A2(
												$elm$core$List$cons,
												y,
												A2(
													$elm$core$List$cons,
													z,
													A2(
														$elm$core$List$cons,
														w,
														A2($elm$core$List$takeTailRec, n - 4, tl))))) : A2(
											$elm$core$List$cons,
											x,
											A2(
												$elm$core$List$cons,
												y,
												A2(
													$elm$core$List$cons,
													z,
													A2(
														$elm$core$List$cons,
														w,
														A3($elm$core$List$takeFast, ctr + 1, n - 4, tl)))));
									} else {
										break _v0$5;
									}
							}
						} else {
							if (_v0.a === 1) {
								break _v0$1;
							} else {
								break _v0$5;
							}
						}
					}
				}
				return list;
			}
			var _v1 = _v0.b;
			var x = _v1.a;
			return _List_fromArray(
				[x]);
		}
	});
var $elm$core$List$take = F2(
	function (n, list) {
		return A3($elm$core$List$takeFast, 0, n, list);
	});
var $author$project$Main$topCategory = function (entries) {
	return A2(
		$elm$core$Maybe$andThen,
		function (_v0) {
			var cat = _v0.a;
			var total = _v0.b;
			return (total > 0) ? $elm$core$Maybe$Just(cat) : $elm$core$Maybe$Nothing;
		},
		$elm$core$List$head(
			A2(
				$elm$core$List$sortBy,
				A2($elm$core$Basics$composeL, $elm$core$Basics$negate, $elm$core$Tuple$second),
				A2(
					$elm$core$List$map,
					function (cat) {
						return _Utils_Tuple2(
							cat,
							$elm$core$List$sum(
								A2(
									$elm$core$List$map,
									function ($) {
										return $.d;
									},
									A2(
										$elm$core$List$filter,
										function (e) {
											return _Utils_eq(e.h, cat);
										},
										entries))));
					},
					$author$project$Main$allCategories))));
};
var $terezka$elm_charts$Internal$Property$NotStacked = function (a) {
	return {$: 0, a: a};
};
var $terezka$elm_charts$Internal$Property$notStacked = F3(
	function (toY, interpolation, presentation) {
		return $terezka$elm_charts$Internal$Property$NotStacked(
			{
				dz: interpolation,
				dN: presentation,
				bv: toY,
				bd: toY,
				cY: $elm$core$Maybe$Nothing,
				d7: function (datum) {
					return A2(
						$elm$core$Maybe$withDefault,
						'N/A',
						A2(
							$elm$core$Maybe$map,
							$elm$core$String$fromFloat,
							toY(datum)));
				},
				c_: F2(
					function (_v0, _v1) {
						return _List_Nil;
					})
			});
	});
var $terezka$elm_charts$Chart$bar = function (y) {
	return A2(
		$terezka$elm_charts$Internal$Property$notStacked,
		A2($elm$core$Basics$composeR, y, $elm$core$Maybe$Just),
		_List_Nil);
};
var $terezka$elm_charts$Chart$BarsElement = F5(
	function (a, b, c, d, e) {
		return {$: 2, a: a, b: b, c: c, d: d, e: e};
	});
var $terezka$elm_charts$Chart$Indexed = function (a) {
	return {$: 0, a: a};
};
var $terezka$elm_charts$Internal$Helpers$apply = F2(
	function (attrs, _default) {
		var apply_ = F2(
			function (_v0, a) {
				var f = _v0;
				return f(a);
			});
		return A3($elm$core$List$foldl, apply_, _default, attrs);
	});
var $elm$svg$Svg$Attributes$class = _VirtualDom_attribute('class');
var $elm$core$List$append = F2(
	function (xs, ys) {
		if (!ys.b) {
			return xs;
		} else {
			return A3($elm$core$List$foldr, $elm$core$List$cons, ys, xs);
		}
	});
var $elm$core$List$concat = function (lists) {
	return A3($elm$core$List$foldr, $elm$core$List$append, _List_Nil, lists);
};
var $elm$core$List$concatMap = F2(
	function (f, list) {
		return $elm$core$List$concat(
			A2($elm$core$List$map, f, list));
	});
var $terezka$elm_charts$Internal$Produce$defaultBars = {o: false, dr: true, X: 0.1, dQ: 0, dR: 0, dU: 0.05, aX: $elm$core$Maybe$Nothing, bi: $elm$core$Maybe$Nothing};
var $terezka$elm_charts$Internal$Coordinates$Position = F4(
	function (x1, x2, y1, y2) {
		return {aX: x1, bi: x2, ee: y1, b5: y2};
	});
var $elm$core$Basics$min = F2(
	function (x, y) {
		return (_Utils_cmp(x, y) < 0) ? x : y;
	});
var $terezka$elm_charts$Internal$Coordinates$foldPosition = F2(
	function (func, data) {
		var fold = F2(
			function (datum, posM) {
				if (!posM.$) {
					var pos = posM.a;
					return $elm$core$Maybe$Just(
						{
							aX: A2(
								$elm$core$Basics$min,
								func(datum).aX,
								pos.aX),
							bi: A2(
								$elm$core$Basics$max,
								func(datum).bi,
								pos.bi),
							ee: A2(
								$elm$core$Basics$min,
								func(datum).ee,
								pos.ee),
							b5: A2(
								$elm$core$Basics$max,
								func(datum).b5,
								pos.b5)
						});
				} else {
					return $elm$core$Maybe$Just(
						func(datum));
				}
			});
		return A2(
			$elm$core$Maybe$withDefault,
			A4($terezka$elm_charts$Internal$Coordinates$Position, 0, 0, 0, 0),
			A3($elm$core$List$foldl, fold, $elm$core$Maybe$Nothing, data));
	});
var $elm$svg$Svg$trustedNode = _VirtualDom_nodeNS('http://www.w3.org/2000/svg');
var $elm$svg$Svg$g = $elm$svg$Svg$trustedNode('g');
var $terezka$elm_charts$Internal$Many$getMembers = function (_v0) {
	var _v1 = _v0.a;
	var x = _v1.a;
	var xs = _v1.b;
	return A2($elm$core$List$cons, x, xs);
};
var $terezka$elm_charts$Internal$Item$Rendered = F2(
	function (a, b) {
		return {$: 0, a: a, b: b};
	});
var $terezka$elm_charts$Internal$Item$map = F2(
	function (func, _v0) {
		var meta = _v0.a;
		var item = _v0.b;
		return A2(
			$terezka$elm_charts$Internal$Item$Rendered,
			{
				cc: meta.cc,
				dj: func(meta.dj),
				dw: meta.dw,
				dB: meta.dB,
				dH: meta.dH,
				dN: meta.dN,
				d1: meta.d1,
				d7: meta.d7,
				aX: meta.aX,
				bi: meta.bi,
				c4: meta.c4
			},
			item);
	});
var $elm$virtual_dom$VirtualDom$map = _VirtualDom_map;
var $elm$svg$Svg$map = $elm$virtual_dom$VirtualDom$map;
var $terezka$elm_charts$Internal$Item$render = function (_v0) {
	var item = _v0.b;
	return item.cL(0);
};
var $terezka$elm_charts$Internal$Legend$BarLegend = F2(
	function (a, b) {
		return {$: 0, a: a, b: b};
	});
var $terezka$elm_charts$Internal$Helpers$Attribute = $elm$core$Basics$identity;
var $terezka$elm_charts$Chart$Attributes$border = function (v) {
	return function (config) {
		return _Utils_update(
			config,
			{N: v});
	};
};
var $terezka$elm_charts$Chart$Attributes$color = function (v) {
	return function (config) {
		return (v === '') ? config : _Utils_update(
			config,
			{cc: v});
	};
};
var $terezka$elm_charts$Internal$Helpers$pink = '#ea60df';
var $terezka$elm_charts$Internal$Svg$defaultBar = {g: _List_Nil, N: 'white', T: 0, cc: $terezka$elm_charts$Internal$Helpers$pink, bz: $elm$core$Maybe$Nothing, dt: 0, du: '', dv: 10, am: 1, dQ: 0, dR: 0};
var $terezka$elm_charts$Chart$Attributes$roundBottom = function (v) {
	return function (config) {
		return _Utils_update(
			config,
			{dQ: v});
	};
};
var $terezka$elm_charts$Chart$Attributes$roundTop = function (v) {
	return function (config) {
		return _Utils_update(
			config,
			{dR: v});
	};
};
var $terezka$elm_charts$Internal$Property$toConfigs = function (property) {
	if (!property.$) {
		var config = property.a;
		return _List_fromArray(
			[config]);
	} else {
		var configs = property.a;
		return configs;
	}
};
var $terezka$elm_charts$Internal$Helpers$blue = '#12A5ED';
var $terezka$elm_charts$Internal$Helpers$brown = '#871c1c';
var $terezka$elm_charts$Internal$Helpers$green = '#71c614';
var $terezka$elm_charts$Internal$Helpers$moss = '#92b42c';
var $terezka$elm_charts$Internal$Helpers$orange = '#FF8400';
var $terezka$elm_charts$Internal$Helpers$purple = '#7b4dff';
var $terezka$elm_charts$Internal$Helpers$red = '#F5325B';
var $elm$core$Dict$fromList = function (assocs) {
	return A3(
		$elm$core$List$foldl,
		F2(
			function (_v0, dict) {
				var key = _v0.a;
				var value = _v0.b;
				return A3($elm$core$Dict$insert, key, value, dict);
			}),
		$elm$core$Dict$empty,
		assocs);
};
var $elm$core$Tuple$pair = F2(
	function (a, b) {
		return _Utils_Tuple2(a, b);
	});
var $elm$core$Dict$sizeHelp = F2(
	function (n, dict) {
		sizeHelp:
		while (true) {
			if (dict.$ === -2) {
				return n;
			} else {
				var left = dict.d;
				var right = dict.e;
				var $temp$n = A2($elm$core$Dict$sizeHelp, n + 1, right),
					$temp$dict = left;
				n = $temp$n;
				dict = $temp$dict;
				continue sizeHelp;
			}
		}
	});
var $elm$core$Dict$size = function (dict) {
	return A2($elm$core$Dict$sizeHelp, 0, dict);
};
var $terezka$elm_charts$Internal$Helpers$toDefault = F3(
	function (_default, items, index) {
		var dict = $elm$core$Dict$fromList(
			A2($elm$core$List$indexedMap, $elm$core$Tuple$pair, items));
		var numOfItems = $elm$core$Dict$size(dict);
		var itemIndex = index % numOfItems;
		return A2(
			$elm$core$Maybe$withDefault,
			_default,
			A2($elm$core$Dict$get, itemIndex, dict));
	});
var $terezka$elm_charts$Internal$Helpers$turquoise = '#22d2ba';
var $terezka$elm_charts$Internal$Helpers$yellow = '#FFCA00';
var $terezka$elm_charts$Internal$Helpers$toDefaultColor = A2(
	$terezka$elm_charts$Internal$Helpers$toDefault,
	$terezka$elm_charts$Internal$Helpers$pink,
	_List_fromArray(
		[$terezka$elm_charts$Internal$Helpers$purple, $terezka$elm_charts$Internal$Helpers$pink, $terezka$elm_charts$Internal$Helpers$blue, $terezka$elm_charts$Internal$Helpers$green, $terezka$elm_charts$Internal$Helpers$red, $terezka$elm_charts$Internal$Helpers$yellow, $terezka$elm_charts$Internal$Helpers$turquoise, $terezka$elm_charts$Internal$Helpers$orange, $terezka$elm_charts$Internal$Helpers$moss, $terezka$elm_charts$Internal$Helpers$brown]));
var $terezka$elm_charts$Internal$Legend$toBarLegends = F3(
	function (elIndex, barsAttrs, properties) {
		var toBarConfig = function (attrs) {
			return A2($terezka$elm_charts$Internal$Helpers$apply, attrs, $terezka$elm_charts$Internal$Svg$defaultBar);
		};
		var barsConfig = A2($terezka$elm_charts$Internal$Helpers$apply, barsAttrs, $terezka$elm_charts$Internal$Produce$defaultBars);
		var toBarLegend = F2(
			function (colorIndex, prop) {
				var rounding = A2($elm$core$Basics$max, barsConfig.dR, barsConfig.dQ);
				var defaultName = 'Property #' + $elm$core$String$fromInt(colorIndex + 1);
				var defaultColor = $terezka$elm_charts$Internal$Helpers$toDefaultColor(colorIndex);
				var defaultAttrs = _List_fromArray(
					[
						$terezka$elm_charts$Chart$Attributes$roundTop(rounding),
						$terezka$elm_charts$Chart$Attributes$roundBottom(rounding),
						$terezka$elm_charts$Chart$Attributes$color(defaultColor),
						$terezka$elm_charts$Chart$Attributes$border(defaultColor)
					]);
				var attrsOrg = _Utils_ap(defaultAttrs, prop.dN);
				var productOrg = toBarConfig(attrsOrg);
				var attrs = _Utils_eq(productOrg.N, defaultColor) ? _Utils_ap(
					attrsOrg,
					_List_fromArray(
						[
							$terezka$elm_charts$Chart$Attributes$border(productOrg.cc)
						])) : attrsOrg;
				return A2(
					$terezka$elm_charts$Internal$Legend$BarLegend,
					A2($elm$core$Maybe$withDefault, defaultName, prop.cY),
					attrs);
			});
		return A2(
			$elm$core$List$indexedMap,
			function (propIndex) {
				return toBarLegend(elIndex + propIndex);
			},
			A2($elm$core$List$concatMap, $terezka$elm_charts$Internal$Property$toConfigs, properties));
	});
var $terezka$elm_charts$Internal$Item$Bar = function (a) {
	return {$: 1, a: a};
};
var $terezka$elm_charts$Internal$Commands$Arc = F7(
	function (a, b, c, d, e, f, g) {
		return {$: 6, a: a, b: b, c: c, d: d, e: e, f: f, g: g};
	});
var $terezka$elm_charts$Internal$Commands$Line = F2(
	function (a, b) {
		return {$: 1, a: a, b: b};
	});
var $terezka$elm_charts$Internal$Commands$Move = F2(
	function (a, b) {
		return {$: 0, a: a, b: b};
	});
var $elm$core$Basics$clamp = F3(
	function (low, high, number) {
		return (_Utils_cmp(number, low) < 0) ? low : ((_Utils_cmp(number, high) > 0) ? high : number);
	});
var $elm$svg$Svg$Attributes$d = _VirtualDom_attribute('d');
var $terezka$elm_charts$Internal$Commands$joinCommands = function (commands) {
	return A2($elm$core$String$join, ' ', commands);
};
var $terezka$elm_charts$Internal$Commands$stringBoolInt = function (bool) {
	return bool ? '1' : '0';
};
var $terezka$elm_charts$Internal$Commands$stringPoint = function (_v0) {
	var x = _v0.a;
	var y = _v0.b;
	return $elm$core$String$fromFloat(x) + (' ' + $elm$core$String$fromFloat(y));
};
var $terezka$elm_charts$Internal$Commands$stringPoints = function (points) {
	return A2(
		$elm$core$String$join,
		',',
		A2($elm$core$List$map, $terezka$elm_charts$Internal$Commands$stringPoint, points));
};
var $terezka$elm_charts$Internal$Commands$stringCommand = function (command) {
	switch (command.$) {
		case 0:
			var x = command.a;
			var y = command.b;
			return 'M' + $terezka$elm_charts$Internal$Commands$stringPoint(
				_Utils_Tuple2(x, y));
		case 1:
			var x = command.a;
			var y = command.b;
			return 'L' + $terezka$elm_charts$Internal$Commands$stringPoint(
				_Utils_Tuple2(x, y));
		case 2:
			var cx1 = command.a;
			var cy1 = command.b;
			var cx2 = command.c;
			var cy2 = command.d;
			var x = command.e;
			var y = command.f;
			return 'C' + $terezka$elm_charts$Internal$Commands$stringPoints(
				_List_fromArray(
					[
						_Utils_Tuple2(cx1, cy1),
						_Utils_Tuple2(cx2, cy2),
						_Utils_Tuple2(x, y)
					]));
		case 3:
			var cx1 = command.a;
			var cy1 = command.b;
			var x = command.c;
			var y = command.d;
			return 'Q' + $terezka$elm_charts$Internal$Commands$stringPoints(
				_List_fromArray(
					[
						_Utils_Tuple2(cx1, cy1),
						_Utils_Tuple2(x, y)
					]));
		case 4:
			var cx1 = command.a;
			var cy1 = command.b;
			var x = command.c;
			var y = command.d;
			return 'Q' + $terezka$elm_charts$Internal$Commands$stringPoints(
				_List_fromArray(
					[
						_Utils_Tuple2(cx1, cy1),
						_Utils_Tuple2(x, y)
					]));
		case 5:
			var x = command.a;
			var y = command.b;
			return 'T' + $terezka$elm_charts$Internal$Commands$stringPoint(
				_Utils_Tuple2(x, y));
		case 6:
			var rx = command.a;
			var ry = command.b;
			var xAxisRotation = command.c;
			var largeArcFlag = command.d;
			var sweepFlag = command.e;
			var x = command.f;
			var y = command.g;
			return 'A ' + $terezka$elm_charts$Internal$Commands$joinCommands(
				_List_fromArray(
					[
						$terezka$elm_charts$Internal$Commands$stringPoint(
						_Utils_Tuple2(rx, ry)),
						$elm$core$String$fromInt(xAxisRotation),
						$terezka$elm_charts$Internal$Commands$stringBoolInt(largeArcFlag),
						$terezka$elm_charts$Internal$Commands$stringBoolInt(sweepFlag),
						$terezka$elm_charts$Internal$Commands$stringPoint(
						_Utils_Tuple2(x, y))
					]));
		default:
			return 'Z';
	}
};
var $terezka$elm_charts$Internal$Commands$Close = {$: 7};
var $terezka$elm_charts$Internal$Commands$CubicBeziers = F6(
	function (a, b, c, d, e, f) {
		return {$: 2, a: a, b: b, c: c, d: d, e: e, f: f};
	});
var $terezka$elm_charts$Internal$Commands$CubicBeziersShort = F4(
	function (a, b, c, d) {
		return {$: 3, a: a, b: b, c: c, d: d};
	});
var $terezka$elm_charts$Internal$Commands$QuadraticBeziers = F4(
	function (a, b, c, d) {
		return {$: 4, a: a, b: b, c: c, d: d};
	});
var $terezka$elm_charts$Internal$Commands$QuadraticBeziersShort = F2(
	function (a, b) {
		return {$: 5, a: a, b: b};
	});
var $terezka$elm_charts$Internal$Coordinates$innerLength = function (axis) {
	return A2($elm$core$Basics$max, 1, (axis.ak - axis.dF) - axis.dE);
};
var $terezka$elm_charts$Internal$Coordinates$innerWidth = function (plane) {
	return $terezka$elm_charts$Internal$Coordinates$innerLength(plane.c3);
};
var $terezka$elm_charts$Internal$Coordinates$range = function (axis) {
	var diff = axis.Q - axis.aa;
	return (diff > 0) ? diff : 1;
};
var $terezka$elm_charts$Internal$Coordinates$scaleSVGX = F2(
	function (plane, value) {
		var range_ = $terezka$elm_charts$Internal$Coordinates$range(plane.c3);
		return ((plane.c3.f ? (range_ - value) : value) * $terezka$elm_charts$Internal$Coordinates$innerWidth(plane)) / range_;
	});
var $terezka$elm_charts$Internal$Coordinates$toSVGX = F2(
	function (plane, value) {
		return A2($terezka$elm_charts$Internal$Coordinates$scaleSVGX, plane, value - plane.c3.aa) + plane.c3.dF;
	});
var $terezka$elm_charts$Internal$Coordinates$innerHeight = function (plane) {
	return $terezka$elm_charts$Internal$Coordinates$innerLength(plane.c4);
};
var $terezka$elm_charts$Internal$Coordinates$scaleSVGY = F2(
	function (plane, value) {
		var range_ = $terezka$elm_charts$Internal$Coordinates$range(plane.c4);
		return ((plane.c4.f ? (range_ - value) : value) * $terezka$elm_charts$Internal$Coordinates$innerHeight(plane)) / range_;
	});
var $terezka$elm_charts$Internal$Coordinates$toSVGY = F2(
	function (plane, value) {
		return A2($terezka$elm_charts$Internal$Coordinates$scaleSVGY, plane, plane.c4.Q - value) + plane.c4.dF;
	});
var $terezka$elm_charts$Internal$Commands$translate = F2(
	function (plane, command) {
		switch (command.$) {
			case 0:
				var x = command.a;
				var y = command.b;
				return A2(
					$terezka$elm_charts$Internal$Commands$Move,
					A2($terezka$elm_charts$Internal$Coordinates$toSVGX, plane, x),
					A2($terezka$elm_charts$Internal$Coordinates$toSVGY, plane, y));
			case 1:
				var x = command.a;
				var y = command.b;
				return A2(
					$terezka$elm_charts$Internal$Commands$Line,
					A2($terezka$elm_charts$Internal$Coordinates$toSVGX, plane, x),
					A2($terezka$elm_charts$Internal$Coordinates$toSVGY, plane, y));
			case 2:
				var cx1 = command.a;
				var cy1 = command.b;
				var cx2 = command.c;
				var cy2 = command.d;
				var x = command.e;
				var y = command.f;
				return A6(
					$terezka$elm_charts$Internal$Commands$CubicBeziers,
					A2($terezka$elm_charts$Internal$Coordinates$toSVGX, plane, cx1),
					A2($terezka$elm_charts$Internal$Coordinates$toSVGY, plane, cy1),
					A2($terezka$elm_charts$Internal$Coordinates$toSVGX, plane, cx2),
					A2($terezka$elm_charts$Internal$Coordinates$toSVGY, plane, cy2),
					A2($terezka$elm_charts$Internal$Coordinates$toSVGX, plane, x),
					A2($terezka$elm_charts$Internal$Coordinates$toSVGY, plane, y));
			case 3:
				var cx1 = command.a;
				var cy1 = command.b;
				var x = command.c;
				var y = command.d;
				return A4(
					$terezka$elm_charts$Internal$Commands$CubicBeziersShort,
					A2($terezka$elm_charts$Internal$Coordinates$toSVGX, plane, cx1),
					A2($terezka$elm_charts$Internal$Coordinates$toSVGY, plane, cy1),
					A2($terezka$elm_charts$Internal$Coordinates$toSVGX, plane, x),
					A2($terezka$elm_charts$Internal$Coordinates$toSVGY, plane, y));
			case 4:
				var cx1 = command.a;
				var cy1 = command.b;
				var x = command.c;
				var y = command.d;
				return A4(
					$terezka$elm_charts$Internal$Commands$QuadraticBeziers,
					A2($terezka$elm_charts$Internal$Coordinates$toSVGX, plane, cx1),
					A2($terezka$elm_charts$Internal$Coordinates$toSVGY, plane, cy1),
					A2($terezka$elm_charts$Internal$Coordinates$toSVGX, plane, x),
					A2($terezka$elm_charts$Internal$Coordinates$toSVGY, plane, y));
			case 5:
				var x = command.a;
				var y = command.b;
				return A2(
					$terezka$elm_charts$Internal$Commands$QuadraticBeziersShort,
					A2($terezka$elm_charts$Internal$Coordinates$toSVGX, plane, x),
					A2($terezka$elm_charts$Internal$Coordinates$toSVGY, plane, y));
			case 6:
				var rx = command.a;
				var ry = command.b;
				var xAxisRotation = command.c;
				var largeArcFlag = command.d;
				var sweepFlag = command.e;
				var x = command.f;
				var y = command.g;
				return A7(
					$terezka$elm_charts$Internal$Commands$Arc,
					rx,
					ry,
					xAxisRotation,
					largeArcFlag,
					sweepFlag,
					A2($terezka$elm_charts$Internal$Coordinates$toSVGX, plane, x),
					A2($terezka$elm_charts$Internal$Coordinates$toSVGY, plane, y));
			default:
				return $terezka$elm_charts$Internal$Commands$Close;
		}
	});
var $terezka$elm_charts$Internal$Commands$description = F2(
	function (plane, commands) {
		return $terezka$elm_charts$Internal$Commands$joinCommands(
			A2(
				$elm$core$List$map,
				A2(
					$elm$core$Basics$composeR,
					$terezka$elm_charts$Internal$Commands$translate(plane),
					$terezka$elm_charts$Internal$Commands$stringCommand),
				commands));
	});
var $elm$svg$Svg$Attributes$fill = _VirtualDom_attribute('fill');
var $elm$svg$Svg$Attributes$fillOpacity = _VirtualDom_attribute('fill-opacity');
var $elm$svg$Svg$path = $elm$svg$Svg$trustedNode('path');
var $terezka$elm_charts$Internal$Coordinates$scaleCartesianX = F2(
	function (plane, value) {
		return (value * $terezka$elm_charts$Internal$Coordinates$range(plane.c3)) / $terezka$elm_charts$Internal$Coordinates$innerWidth(plane);
	});
var $terezka$elm_charts$Internal$Coordinates$scaleCartesianY = F2(
	function (plane, value) {
		return (value * $terezka$elm_charts$Internal$Coordinates$range(plane.c4)) / $terezka$elm_charts$Internal$Coordinates$innerHeight(plane);
	});
var $elm$svg$Svg$Attributes$stroke = _VirtualDom_attribute('stroke');
var $elm$svg$Svg$Attributes$strokeOpacity = _VirtualDom_attribute('stroke-opacity');
var $elm$svg$Svg$Attributes$strokeWidth = _VirtualDom_attribute('stroke-width');
var $elm$svg$Svg$circle = $elm$svg$Svg$trustedNode('circle');
var $elm$svg$Svg$Attributes$cx = _VirtualDom_attribute('cx');
var $elm$svg$Svg$Attributes$cy = _VirtualDom_attribute('cy');
var $elm$svg$Svg$defs = $elm$svg$Svg$trustedNode('defs');
var $elm$svg$Svg$Attributes$height = _VirtualDom_attribute('height');
var $elm$svg$Svg$Attributes$id = _VirtualDom_attribute('id');
var $elm$svg$Svg$line = $elm$svg$Svg$trustedNode('line');
var $elm$svg$Svg$linearGradient = $elm$svg$Svg$trustedNode('linearGradient');
var $elm$svg$Svg$Attributes$offset = _VirtualDom_attribute('offset');
var $elm$svg$Svg$pattern = $elm$svg$Svg$trustedNode('pattern');
var $elm$svg$Svg$Attributes$patternTransform = _VirtualDom_attribute('patternTransform');
var $elm$svg$Svg$Attributes$patternUnits = _VirtualDom_attribute('patternUnits');
var $elm$svg$Svg$Attributes$r = _VirtualDom_attribute('r');
var $elm$core$String$replace = F3(
	function (before, after, string) {
		return A2(
			$elm$core$String$join,
			after,
			A2($elm$core$String$split, before, string));
	});
var $elm$svg$Svg$stop = $elm$svg$Svg$trustedNode('stop');
var $elm$svg$Svg$Attributes$stopColor = _VirtualDom_attribute('stop-color');
var $elm$svg$Svg$Attributes$width = _VirtualDom_attribute('width');
var $elm$svg$Svg$Attributes$x1 = _VirtualDom_attribute('x1');
var $elm$svg$Svg$Attributes$x2 = _VirtualDom_attribute('x2');
var $elm$svg$Svg$Attributes$y = _VirtualDom_attribute('y');
var $elm$svg$Svg$Attributes$y1 = _VirtualDom_attribute('y1');
var $elm$svg$Svg$Attributes$y2 = _VirtualDom_attribute('y2');
var $terezka$elm_charts$Internal$Svg$toPattern = F2(
	function (defaultColor, design) {
		var toPatternId = function (props) {
			return A3(
				$elm$core$String$replace,
				'(',
				'-',
				A3(
					$elm$core$String$replace,
					')',
					'-',
					A3(
						$elm$core$String$replace,
						'.',
						'-',
						A3(
							$elm$core$String$replace,
							',',
							'-',
							A3(
								$elm$core$String$replace,
								' ',
								'-',
								A2(
									$elm$core$String$join,
									'-',
									_Utils_ap(
										_List_fromArray(
											[
												'elm-charts__pattern',
												function () {
												switch (design.$) {
													case 0:
														return 'striped';
													case 1:
														return 'dotted';
													default:
														return 'gradient';
												}
											}()
											]),
										props)))))));
		};
		var toPatternDefs = F4(
			function (id, spacing, rotate, inside) {
				return A2(
					$elm$svg$Svg$defs,
					_List_Nil,
					_List_fromArray(
						[
							A2(
							$elm$svg$Svg$pattern,
							_List_fromArray(
								[
									$elm$svg$Svg$Attributes$id(id),
									$elm$svg$Svg$Attributes$patternUnits('userSpaceOnUse'),
									$elm$svg$Svg$Attributes$width(
									$elm$core$String$fromFloat(spacing)),
									$elm$svg$Svg$Attributes$height(
									$elm$core$String$fromFloat(spacing)),
									$elm$svg$Svg$Attributes$patternTransform(
									'rotate(' + ($elm$core$String$fromFloat(rotate) + ')'))
								]),
							_List_fromArray(
								[inside]))
						]));
			});
		var _v0 = function () {
			switch (design.$) {
				case 0:
					var edits = design.a;
					var config = A2(
						$terezka$elm_charts$Internal$Helpers$apply,
						edits,
						{cc: defaultColor, B: 45, dU: 4, c2: 3});
					var theId = toPatternId(
						_List_fromArray(
							[
								config.cc,
								$elm$core$String$fromFloat(config.c2),
								$elm$core$String$fromFloat(config.dU),
								$elm$core$String$fromFloat(config.B)
							]));
					return _Utils_Tuple2(
						A4(
							toPatternDefs,
							theId,
							config.dU,
							config.B,
							A2(
								$elm$svg$Svg$line,
								_List_fromArray(
									[
										$elm$svg$Svg$Attributes$x1('0'),
										$elm$svg$Svg$Attributes$y('0'),
										$elm$svg$Svg$Attributes$x2('0'),
										$elm$svg$Svg$Attributes$y2(
										$elm$core$String$fromFloat(config.dU)),
										$elm$svg$Svg$Attributes$stroke(config.cc),
										$elm$svg$Svg$Attributes$strokeWidth(
										$elm$core$String$fromFloat(config.c2))
									]),
								_List_Nil)),
						theId);
				case 1:
					var edits = design.a;
					var config = A2(
						$terezka$elm_charts$Internal$Helpers$apply,
						edits,
						{cc: defaultColor, B: 45, dU: 4, c2: 3});
					var theId = toPatternId(
						_List_fromArray(
							[
								config.cc,
								$elm$core$String$fromFloat(config.c2),
								$elm$core$String$fromFloat(config.dU),
								$elm$core$String$fromFloat(config.B)
							]));
					return _Utils_Tuple2(
						A4(
							toPatternDefs,
							theId,
							config.dU,
							config.B,
							A2(
								$elm$svg$Svg$circle,
								_List_fromArray(
									[
										$elm$svg$Svg$Attributes$fill(config.cc),
										$elm$svg$Svg$Attributes$cx(
										$elm$core$String$fromFloat(config.c2 / 3)),
										$elm$svg$Svg$Attributes$cy(
										$elm$core$String$fromFloat(config.c2 / 3)),
										$elm$svg$Svg$Attributes$r(
										$elm$core$String$fromFloat(config.c2 / 3))
									]),
								_List_Nil)),
						theId);
				default:
					var edits = design.a;
					var colors = _Utils_eq(edits, _List_Nil) ? _List_fromArray(
						[defaultColor, 'white']) : edits;
					var theId = toPatternId(colors);
					var totalColors = $elm$core$List$length(colors);
					var toPercentage = function (i) {
						return (i * 100) / (totalColors - 1);
					};
					var toStop = F2(
						function (i, c) {
							return A2(
								$elm$svg$Svg$stop,
								_List_fromArray(
									[
										$elm$svg$Svg$Attributes$offset(
										$elm$core$String$fromFloat(
											toPercentage(i)) + '%'),
										$elm$svg$Svg$Attributes$stopColor(c)
									]),
								_List_Nil);
						});
					return _Utils_Tuple2(
						A2(
							$elm$svg$Svg$defs,
							_List_Nil,
							_List_fromArray(
								[
									A2(
									$elm$svg$Svg$linearGradient,
									_List_fromArray(
										[
											$elm$svg$Svg$Attributes$id(theId),
											$elm$svg$Svg$Attributes$x1('0'),
											$elm$svg$Svg$Attributes$x2('0'),
											$elm$svg$Svg$Attributes$y1('0'),
											$elm$svg$Svg$Attributes$y2('1')
										]),
									A2($elm$core$List$indexedMap, toStop, colors))
								])),
						theId);
			}
		}();
		var patternDefs = _v0.a;
		var patternId = _v0.b;
		return _Utils_Tuple2(patternDefs, 'url(#' + (patternId + ')'));
	});
var $elm$virtual_dom$VirtualDom$mapAttribute = _VirtualDom_mapAttribute;
var $elm$html$Html$Attributes$map = $elm$virtual_dom$VirtualDom$mapAttribute;
var $terezka$elm_charts$Internal$Svg$withAttrs = F3(
	function (attrs, toEl, defaultAttrs) {
		return toEl(
			_Utils_ap(
				defaultAttrs,
				A2(
					$elm$core$List$map,
					$elm$html$Html$Attributes$map($elm$core$Basics$never),
					attrs)));
	});
var $elm$svg$Svg$Attributes$clipPath = _VirtualDom_attribute('clip-path');
var $terezka$elm_charts$Internal$Coordinates$toId = function (plane) {
	var numToStr = A2(
		$elm$core$Basics$composeR,
		$elm$core$String$fromFloat,
		A2($elm$core$String$replace, '.', '-'));
	return A2(
		$elm$core$String$join,
		'_',
		_List_fromArray(
			[
				'elm-charts__id',
				numToStr(plane.c3.ak),
				numToStr(plane.c3.aa),
				numToStr(plane.c3.Q),
				numToStr(plane.c3.dF),
				numToStr(plane.c3.dE),
				numToStr(plane.c4.ak),
				numToStr(plane.c4.aa),
				numToStr(plane.c4.Q),
				numToStr(plane.c4.dF),
				numToStr(plane.c4.dE)
			]));
};
var $terezka$elm_charts$Internal$Svg$withinChartArea = function (plane) {
	return $elm$svg$Svg$Attributes$clipPath(
		'url(#' + ($terezka$elm_charts$Internal$Coordinates$toId(plane) + ')'));
};
var $terezka$elm_charts$Internal$Svg$bar = F3(
	function (plane, config, point) {
		var viewBar = F6(
			function (fill, fillOpacity, border, borderWidth, strokeOpacity, cmds) {
				return A4(
					$terezka$elm_charts$Internal$Svg$withAttrs,
					config.g,
					$elm$svg$Svg$path,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$class('elm-charts__bar'),
							$elm$svg$Svg$Attributes$fill(fill),
							$elm$svg$Svg$Attributes$fillOpacity(
							$elm$core$String$fromFloat(fillOpacity)),
							$elm$svg$Svg$Attributes$stroke(border),
							$elm$svg$Svg$Attributes$strokeWidth(
							$elm$core$String$fromFloat(borderWidth)),
							$elm$svg$Svg$Attributes$strokeOpacity(
							$elm$core$String$fromFloat(strokeOpacity)),
							$elm$svg$Svg$Attributes$d(
							A2($terezka$elm_charts$Internal$Commands$description, plane, cmds)),
							$terezka$elm_charts$Internal$Svg$withinChartArea(plane)
						]),
					_List_Nil);
			});
		var highlightColor = (config.du === '') ? config.cc : config.du;
		var borderWidthCarY = A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianY, plane, config.T / 2);
		var highlightWidthCarY = borderWidthCarY + A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianY, plane, config.dv / 2);
		var borderWidthCarX = A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianX, plane, config.T / 2);
		var highlightWidthCarX = borderWidthCarX + A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianX, plane, config.dv / 2);
		var pos = {
			aX: A2($elm$core$Basics$min, point.aX, point.bi) + borderWidthCarX,
			bi: A2($elm$core$Basics$max, point.aX, point.bi) - borderWidthCarX,
			ee: A2($elm$core$Basics$min, point.ee, point.b5) + borderWidthCarY,
			b5: A2($elm$core$Basics$max, point.ee, point.b5) - borderWidthCarY
		};
		var height = $elm$core$Basics$abs(pos.b5 - pos.ee);
		var highlightPos = {aX: pos.aX - highlightWidthCarX, bi: pos.bi + highlightWidthCarX, ee: pos.ee - highlightWidthCarY, b5: pos.b5 + highlightWidthCarY};
		var width = $elm$core$Basics$abs(pos.bi - pos.aX);
		var roundingBottom = (A2($terezka$elm_charts$Internal$Coordinates$scaleSVGX, plane, width) * 0.5) * A3($elm$core$Basics$clamp, 0, 1, config.dQ);
		var radiusBottomX = A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianX, plane, roundingBottom);
		var radiusBottomY = A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianY, plane, roundingBottom);
		var roundingTop = (A2($terezka$elm_charts$Internal$Coordinates$scaleSVGX, plane, width) * 0.5) * A3($elm$core$Basics$clamp, 0, 1, config.dR);
		var radiusTopX = A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianX, plane, roundingTop);
		var radiusTopY = A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianY, plane, roundingTop);
		var _v0 = ((((height - (radiusTopY * 0.8)) - (radiusBottomY * 0.8)) <= 0) || (((width - (radiusTopX * 0.8)) - (radiusBottomX * 0.8)) <= 0)) ? _Utils_Tuple2(0, 0) : _Utils_Tuple2(config.dR, config.dQ);
		var roundTop = _v0.a;
		var roundBottom = _v0.b;
		var _v1 = function () {
			if (_Utils_eq(pos.ee, pos.b5)) {
				return _Utils_Tuple2(_List_Nil, _List_Nil);
			} else {
				var _v2 = _Utils_Tuple2(roundTop > 0, roundBottom > 0);
				if (!_v2.a) {
					if (!_v2.b) {
						return _Utils_Tuple2(
							_List_fromArray(
								[
									A2($terezka$elm_charts$Internal$Commands$Move, pos.aX, pos.ee),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.aX, pos.b5),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.bi, pos.b5),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.bi, pos.ee),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.aX, pos.ee)
								]),
							_List_fromArray(
								[
									A2($terezka$elm_charts$Internal$Commands$Move, highlightPos.aX, pos.ee),
									A2($terezka$elm_charts$Internal$Commands$Line, highlightPos.aX, highlightPos.b5),
									A2($terezka$elm_charts$Internal$Commands$Line, highlightPos.bi, highlightPos.b5),
									A2($terezka$elm_charts$Internal$Commands$Line, highlightPos.bi, pos.ee),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.bi, pos.ee),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.bi, pos.b5),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.aX, pos.b5),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.aX, pos.ee)
								]));
					} else {
						return _Utils_Tuple2(
							_List_fromArray(
								[
									A2($terezka$elm_charts$Internal$Commands$Move, pos.aX + radiusBottomX, pos.ee),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingBottom, roundingBottom, -45, false, true, pos.aX, pos.ee + radiusBottomY),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.aX, pos.b5),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.bi, pos.b5),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.bi, pos.ee + radiusBottomY),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingBottom, roundingBottom, -45, false, true, pos.bi - radiusBottomX, pos.ee),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.aX + radiusBottomX, pos.ee)
								]),
							_List_fromArray(
								[
									A2($terezka$elm_charts$Internal$Commands$Move, highlightPos.aX + radiusBottomX, highlightPos.ee),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingBottom, roundingBottom, -45, false, true, highlightPos.aX, highlightPos.ee + radiusBottomY),
									A2($terezka$elm_charts$Internal$Commands$Line, highlightPos.aX, highlightPos.b5),
									A2($terezka$elm_charts$Internal$Commands$Line, highlightPos.bi, highlightPos.b5),
									A2($terezka$elm_charts$Internal$Commands$Line, highlightPos.bi, highlightPos.ee + radiusBottomY),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingBottom, roundingBottom, -45, false, true, highlightPos.bi - radiusBottomX, highlightPos.ee),
									A2($terezka$elm_charts$Internal$Commands$Line, highlightPos.aX + radiusBottomX, highlightPos.ee),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.bi - radiusBottomX, pos.ee),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingBottom, roundingBottom, -45, false, false, pos.bi, pos.ee + radiusBottomY),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.bi, pos.b5),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.aX, pos.b5),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.aX, pos.ee + radiusBottomY),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.bi, pos.ee)
								]));
					}
				} else {
					if (!_v2.b) {
						return _Utils_Tuple2(
							_List_fromArray(
								[
									A2($terezka$elm_charts$Internal$Commands$Move, pos.aX, pos.ee),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.aX, pos.b5 - radiusTopY),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingTop, roundingTop, -45, false, true, pos.aX + radiusTopX, pos.b5),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.bi - radiusTopX, pos.b5),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingTop, roundingTop, -45, false, true, pos.bi, pos.b5 - radiusTopY),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.bi, pos.ee),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.aX, pos.ee)
								]),
							_List_fromArray(
								[
									A2($terezka$elm_charts$Internal$Commands$Move, highlightPos.aX, pos.ee),
									A2($terezka$elm_charts$Internal$Commands$Line, highlightPos.aX, highlightPos.b5 - radiusTopY),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingTop, roundingTop, -45, false, true, highlightPos.aX + radiusTopX, highlightPos.b5),
									A2($terezka$elm_charts$Internal$Commands$Line, highlightPos.bi - radiusTopX, highlightPos.b5),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingTop, roundingTop, -45, false, true, highlightPos.bi, highlightPos.b5 - radiusTopY),
									A2($terezka$elm_charts$Internal$Commands$Line, highlightPos.bi, pos.ee),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.bi, pos.ee),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.bi, pos.b5 - radiusTopY),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingTop, roundingTop, -45, false, false, pos.bi - radiusTopX, pos.b5),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.aX + radiusTopX, pos.b5),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingTop, roundingTop, -45, false, false, pos.aX, pos.b5 - radiusTopY),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.aX, pos.ee)
								]));
					} else {
						return _Utils_Tuple2(
							_List_fromArray(
								[
									A2($terezka$elm_charts$Internal$Commands$Move, pos.aX + radiusBottomX, pos.ee),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingBottom, roundingBottom, -45, false, true, pos.aX, pos.ee + radiusBottomY),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.aX, pos.b5 - radiusTopY),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingTop, roundingTop, -45, false, true, pos.aX + radiusTopX, pos.b5),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.bi - radiusTopX, pos.b5),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingTop, roundingTop, -45, false, true, pos.bi, pos.b5 - radiusTopY),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.bi, pos.ee + radiusBottomY),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingBottom, roundingBottom, -45, false, true, pos.bi - radiusBottomX, pos.ee),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.aX + radiusBottomX, pos.ee)
								]),
							_List_fromArray(
								[
									A2($terezka$elm_charts$Internal$Commands$Move, highlightPos.aX + radiusBottomX, highlightPos.ee),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingBottom, roundingBottom, -45, false, true, highlightPos.aX, highlightPos.ee + radiusBottomY),
									A2($terezka$elm_charts$Internal$Commands$Line, highlightPos.aX, highlightPos.b5 - radiusTopY),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingTop, roundingTop, -45, false, true, highlightPos.aX + radiusTopX, highlightPos.b5),
									A2($terezka$elm_charts$Internal$Commands$Line, highlightPos.bi - radiusTopX, highlightPos.b5),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingTop, roundingTop, -45, false, true, highlightPos.bi, highlightPos.b5 - radiusTopY),
									A2($terezka$elm_charts$Internal$Commands$Line, highlightPos.bi, highlightPos.ee + radiusBottomY),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingBottom, roundingBottom, -45, false, true, highlightPos.bi - radiusBottomX, highlightPos.ee),
									A2($terezka$elm_charts$Internal$Commands$Line, highlightPos.aX + radiusBottomX, highlightPos.ee),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.bi - radiusBottomX, pos.ee),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingBottom, roundingBottom, -45, false, false, pos.bi, pos.ee + radiusBottomY),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.bi, pos.b5 - radiusTopY),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingTop, roundingTop, -45, false, false, pos.bi - radiusTopX, pos.b5),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.aX + radiusTopX, pos.b5),
									A7($terezka$elm_charts$Internal$Commands$Arc, roundingTop, roundingTop, -45, false, false, pos.aX, pos.b5 - radiusTopY),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.aX, pos.ee + radiusBottomY),
									A2($terezka$elm_charts$Internal$Commands$Line, pos.bi, pos.ee)
								]));
					}
				}
			}
		}();
		var commands = _v1.a;
		var highlightCommands = _v1.b;
		var viewAuraBar = function (fill) {
			return (!config.dt) ? A6(viewBar, fill, config.am, config.N, config.T, 1, commands) : A2(
				$elm$svg$Svg$g,
				_List_fromArray(
					[
						$elm$svg$Svg$Attributes$class('elm-charts__bar-with-highlight')
					]),
				_List_fromArray(
					[
						A6(viewBar, highlightColor, config.dt, 'transparent', 0, 0, highlightCommands),
						A6(viewBar, fill, config.am, config.N, config.T, 1, commands)
					]));
		};
		var _v3 = config.bz;
		if (_v3.$ === 1) {
			return viewAuraBar(config.cc);
		} else {
			var design = _v3.a;
			var _v4 = A2($terezka$elm_charts$Internal$Svg$toPattern, config.cc, design);
			var patternDefs = _v4.a;
			var fill = _v4.b;
			return A2(
				$elm$svg$Svg$g,
				_List_fromArray(
					[
						$elm$svg$Svg$Attributes$class('elm-charts__bar-with-pattern')
					]),
				_List_fromArray(
					[
						patternDefs,
						viewAuraBar(fill)
					]));
		}
	});
var $terezka$elm_charts$Internal$Coordinates$convertX = F3(
	function (topLevel, plane, x) {
		return topLevel.c3.aa + ($terezka$elm_charts$Internal$Coordinates$range(topLevel.c3) * ((x - plane.c3.aa) / $terezka$elm_charts$Internal$Coordinates$range(plane.c3)));
	});
var $terezka$elm_charts$Internal$Coordinates$convertY = F3(
	function (topLevel, plane, y) {
		return topLevel.c4.aa + ($terezka$elm_charts$Internal$Coordinates$range(topLevel.c4) * ((y - plane.c4.aa) / $terezka$elm_charts$Internal$Coordinates$range(plane.c4)));
	});
var $terezka$elm_charts$Internal$Coordinates$convertPos = F3(
	function (topLevel, plane, pos) {
		return {
			aX: A3($terezka$elm_charts$Internal$Coordinates$convertX, topLevel, plane, pos.aX),
			bi: A3($terezka$elm_charts$Internal$Coordinates$convertX, topLevel, plane, pos.bi),
			ee: A3($terezka$elm_charts$Internal$Coordinates$convertY, topLevel, plane, pos.ee),
			b5: A3($terezka$elm_charts$Internal$Coordinates$convertY, topLevel, plane, pos.b5)
		};
	});
var $terezka$elm_charts$Internal$Item$getLimits = function (_v0) {
	var item = _v0.b;
	return item.I;
};
var $terezka$elm_charts$Internal$Item$getPosition = function (_v0) {
	var item = _v0.b;
	return item.F;
};
var $elm$html$Html$table = _VirtualDom_node('table');
var $terezka$elm_charts$Internal$Produce$toBin = F5(
	function (barsConfig, index, prevM, curr, nextM) {
		var _v0 = _Utils_Tuple2(barsConfig.aX, barsConfig.bi);
		if (_v0.a.$ === 1) {
			if (_v0.b.$ === 1) {
				var _v1 = _v0.a;
				var _v2 = _v0.b;
				return {dj: curr, cj: (index + 1) + 0.5, b1: (index + 1) - 0.5};
			} else {
				var _v8 = _v0.a;
				var toX2 = _v0.b.a;
				var _v9 = _Utils_Tuple2(prevM, nextM);
				if (!_v9.a.$) {
					var prev = _v9.a.a;
					return {
						dj: curr,
						cj: toX2(curr),
						b1: toX2(prev)
					};
				} else {
					if (!_v9.b.$) {
						var _v10 = _v9.a;
						var next = _v9.b.a;
						return {
							dj: curr,
							cj: toX2(curr),
							b1: toX2(curr) - (toX2(next) - toX2(curr))
						};
					} else {
						var _v11 = _v9.a;
						var _v12 = _v9.b;
						return {
							dj: curr,
							cj: toX2(curr),
							b1: toX2(curr) - 1
						};
					}
				}
			}
		} else {
			if (_v0.b.$ === 1) {
				var toX1 = _v0.a.a;
				var _v3 = _v0.b;
				var _v4 = _Utils_Tuple2(prevM, nextM);
				if (!_v4.b.$) {
					var next = _v4.b.a;
					return {
						dj: curr,
						cj: toX1(next),
						b1: toX1(curr)
					};
				} else {
					if (!_v4.a.$) {
						var prev = _v4.a.a;
						var _v5 = _v4.b;
						return {
							dj: curr,
							cj: toX1(curr) + (toX1(curr) - toX1(prev)),
							b1: toX1(curr)
						};
					} else {
						var _v6 = _v4.a;
						var _v7 = _v4.b;
						return {
							dj: curr,
							cj: toX1(curr) + 1,
							b1: toX1(curr)
						};
					}
				}
			} else {
				var toX1 = _v0.a.a;
				var toX2 = _v0.b.a;
				return {
					dj: curr,
					cj: toX2(curr),
					b1: toX1(curr)
				};
			}
		}
	});
var $terezka$elm_charts$Internal$Produce$toDefaultName = F2(
	function (ids, name) {
		return A2(
			$elm$core$Maybe$withDefault,
			'Property #' + $elm$core$String$fromInt(ids.c7 + 1),
			name);
	});
var $terezka$elm_charts$Internal$Item$tooltip = function (_v0) {
	var item = _v0.b;
	return item.d6(0);
};
var $elm$html$Html$td = _VirtualDom_node('td');
var $elm$html$Html$tr = _VirtualDom_node('tr');
var $terezka$elm_charts$Internal$Produce$tooltipRow = F3(
	function (color, title, text) {
		return A2(
			$elm$html$Html$tr,
			_List_Nil,
			_List_fromArray(
				[
					A2(
					$elm$html$Html$td,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'color', color),
							A2($elm$html$Html$Attributes$style, 'padding', '0'),
							A2($elm$html$Html$Attributes$style, 'padding-right', '3px')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(title + ':')
						])),
					A2(
					$elm$html$Html$td,
					_List_fromArray(
						[
							A2($elm$html$Html$Attributes$style, 'text-align', 'right'),
							A2($elm$html$Html$Attributes$style, 'padding', '0')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(text)
						]))
				]));
	});
var $elm$core$List$unzip = function (pairs) {
	var step = F2(
		function (_v0, _v1) {
			var x = _v0.a;
			var y = _v0.b;
			var xs = _v1.a;
			var ys = _v1.b;
			return _Utils_Tuple2(
				A2($elm$core$List$cons, x, xs),
				A2($elm$core$List$cons, y, ys));
		});
	return A3(
		$elm$core$List$foldr,
		step,
		_Utils_Tuple2(_List_Nil, _List_Nil),
		pairs);
};
var $terezka$elm_charts$Internal$Produce$updateBorder = F2(
	function (defaultColor, product) {
		return _Utils_eq(product.N, defaultColor) ? _Utils_update(
			product,
			{N: product.cc}) : product;
	});
var $terezka$elm_charts$Internal$Produce$updateColorIfGradientIsSet = F2(
	function (defaultColor, product) {
		var _v0 = product.bz;
		if (((!_v0.$) && (_v0.a.$ === 2)) && _v0.a.a.b) {
			var _v1 = _v0.a.a;
			var first = _v1.a;
			return _Utils_eq(product.cc, defaultColor) ? _Utils_update(
				product,
				{cc: first}) : product;
		} else {
			return product;
		}
	});
var $terezka$elm_charts$Internal$Helpers$withFirst = F2(
	function (xs, func) {
		if (xs.b) {
			var x = xs.a;
			var rest = xs.b;
			return $elm$core$Maybe$Just(
				A2(func, x, rest));
		} else {
			return $elm$core$Maybe$Nothing;
		}
	});
var $terezka$elm_charts$Internal$Helpers$withSurround = F2(
	function (all, func) {
		var fold = F4(
			function (index, prev, acc, list) {
				fold:
				while (true) {
					if (list.b) {
						if (list.b.b) {
							var a = list.a;
							var _v1 = list.b;
							var b = _v1.a;
							var rest = _v1.b;
							var $temp$index = index + 1,
								$temp$prev = $elm$core$Maybe$Just(a),
								$temp$acc = _Utils_ap(
								acc,
								_List_fromArray(
									[
										A4(
										func,
										index,
										prev,
										a,
										$elm$core$Maybe$Just(b))
									])),
								$temp$list = A2($elm$core$List$cons, b, rest);
							index = $temp$index;
							prev = $temp$prev;
							acc = $temp$acc;
							list = $temp$list;
							continue fold;
						} else {
							var a = list.a;
							return _Utils_ap(
								acc,
								_List_fromArray(
									[
										A4(func, index, prev, a, $elm$core$Maybe$Nothing)
									]));
						}
					} else {
						return acc;
					}
				}
			});
		return A4(fold, 0, $elm$core$Maybe$Nothing, _List_Nil, all);
	});
var $terezka$elm_charts$Internal$Produce$toBarSeries = F4(
	function (elementIndex, barsAttrs, properties, data) {
		var barsConfig = A2($terezka$elm_charts$Internal$Helpers$apply, barsAttrs, $terezka$elm_charts$Internal$Produce$defaultBars);
		var numOfStacks = barsConfig.dr ? $elm$core$List$length(properties) : 1;
		var forEachDataPoint = F7(
			function (absoluteIndex, stackSeriesConfigIndex, barSeriesConfigIndex, numOfBarsInStack, barSeriesConfig, dataIndex, bin) {
				var ySum = barSeriesConfig.bd(bin.dj);
				var y = barSeriesConfig.bv(bin.dj);
				var start = bin.b1;
				var minY = (numOfBarsInStack > 1) ? $elm$core$Basics$max(0) : $elm$core$Basics$identity;
				var y1 = minY(
					A2($elm$core$Maybe$withDefault, 0, ySum) - A2($elm$core$Maybe$withDefault, 0, y));
				var y2 = minY(
					A2($elm$core$Maybe$withDefault, 0, ySum));
				var isSingle = numOfBarsInStack === 1;
				var identification = {c7: absoluteIndex, cd: dataIndex, $7: elementIndex, dT: barSeriesConfigIndex, dV: stackSeriesConfigIndex};
				var isBottom = _Utils_eq(identification.dT, numOfBarsInStack - 1);
				var roundBottom = (isSingle || isBottom) ? barsConfig.dQ : 0;
				var isTop = !identification.dT;
				var roundTop = (isSingle || isTop) ? barsConfig.dR : 0;
				var end = bin.cj;
				var length = end - start;
				var margin = length * barsConfig.X;
				var spacing = length * barsConfig.dU;
				var width = ((length - (margin * 2)) - ((numOfStacks - 1) * spacing)) / numOfStacks;
				var offset = barsConfig.dr ? ((identification.dV * width) + (identification.dV * spacing)) : 0;
				var x1 = (start + margin) + offset;
				var x2 = ((start + margin) + offset) + width;
				var position = {aX: x1, bi: x2, ee: y1, b5: y2};
				var limits = {
					aX: start,
					bi: end,
					ee: A2($elm$core$Basics$min, y1, y2),
					b5: A2($elm$core$Basics$max, y1, y2)
				};
				var defaultColor = $terezka$elm_charts$Internal$Helpers$toDefaultColor(identification.c7);
				var basicAttributes = _List_fromArray(
					[
						$terezka$elm_charts$Chart$Attributes$roundTop(roundTop),
						$terezka$elm_charts$Chart$Attributes$roundBottom(roundBottom),
						$terezka$elm_charts$Chart$Attributes$color(defaultColor),
						$terezka$elm_charts$Chart$Attributes$border(defaultColor)
					]);
				var barPresentationConfig = A2(
					$terezka$elm_charts$Internal$Produce$updateBorder,
					defaultColor,
					A2(
						$terezka$elm_charts$Internal$Produce$updateColorIfGradientIsSet,
						defaultColor,
						A2(
							$terezka$elm_charts$Internal$Helpers$apply,
							_Utils_ap(
								basicAttributes,
								_Utils_ap(
									barSeriesConfig.dN,
									A2(barSeriesConfig.c_, identification, bin.dj))),
							$terezka$elm_charts$Internal$Svg$defaultBar)));
				return _Utils_Tuple2(
					limits,
					F2(
						function (topLevel, localPlane) {
							return A2(
								$terezka$elm_charts$Internal$Item$Rendered,
								{
									cc: barPresentationConfig.cc,
									dj: bin.dj,
									dw: identification,
									dB: !_Utils_eq(y, $elm$core$Maybe$Nothing),
									dH: barSeriesConfig.cY,
									dN: $terezka$elm_charts$Internal$Item$Bar(barPresentationConfig),
									d1: $elm$core$Basics$identity,
									d7: barSeriesConfig.d7(bin.dj),
									aX: start,
									bi: end,
									c4: A2($elm$core$Maybe$withDefault, 0, y)
								},
								{
									I: limits,
									dC: A3($terezka$elm_charts$Internal$Coordinates$convertPos, topLevel, localPlane, limits),
									dD: localPlane,
									dL: topLevel,
									F: position,
									dM: A3($terezka$elm_charts$Internal$Coordinates$convertPos, topLevel, localPlane, position),
									cL: function (_v11) {
										return A3($terezka$elm_charts$Internal$Svg$bar, localPlane, barPresentationConfig, position);
									},
									d6: function (_v12) {
										return _List_fromArray(
											[
												A3(
												$terezka$elm_charts$Internal$Produce$tooltipRow,
												barPresentationConfig.cc,
												A2($terezka$elm_charts$Internal$Produce$toDefaultName, identification, barSeriesConfig.cY),
												barSeriesConfig.d7(bin.dj))
											]);
									}
								});
						}));
			});
		var forEachBarSeriesConfig = F6(
			function (bins, absoluteIndex, stackSeriesConfigIndex, numOfBarsInStack, barSeriesConfigIndex, barSeriesConfig) {
				var absoluteIndexNew = absoluteIndex + barSeriesConfigIndex;
				var _v8 = $elm$core$List$unzip(
					A2(
						$elm$core$List$indexedMap,
						A5(forEachDataPoint, absoluteIndexNew, stackSeriesConfigIndex, barSeriesConfigIndex, numOfBarsInStack, barSeriesConfig),
						bins));
				var limits = _v8.a;
				var toBarItems = _v8.b;
				return _Utils_Tuple2(
					limits,
					F2(
						function (topLevel, localPlane) {
							var barItems = A2(
								$elm$core$List$map,
								function (i) {
									return A2(i, topLevel, localPlane);
								},
								toBarItems);
							return A2(
								$terezka$elm_charts$Internal$Helpers$withFirst,
								barItems,
								F2(
									function (first, rest) {
										var groupPosition = A2($terezka$elm_charts$Internal$Coordinates$foldPosition, $terezka$elm_charts$Internal$Item$getPosition, barItems);
										var groupLimits = A2($terezka$elm_charts$Internal$Coordinates$foldPosition, $terezka$elm_charts$Internal$Item$getLimits, barItems);
										return A2(
											$terezka$elm_charts$Internal$Item$Rendered,
											_Utils_Tuple2(first, rest),
											{
												I: groupLimits,
												dC: A3($terezka$elm_charts$Internal$Coordinates$convertPos, topLevel, localPlane, groupLimits),
												dD: localPlane,
												dL: topLevel,
												F: groupPosition,
												dM: A3($terezka$elm_charts$Internal$Coordinates$convertPos, topLevel, localPlane, groupPosition),
												cL: function (_v9) {
													return A2(
														$elm$svg$Svg$g,
														_List_fromArray(
															[
																$elm$svg$Svg$Attributes$class('elm-charts__series')
															]),
														A2($elm$core$List$map, $terezka$elm_charts$Internal$Item$render, barItems));
												},
												d6: function (_v10) {
													return _List_fromArray(
														[
															A2(
															$elm$html$Html$table,
															_List_fromArray(
																[
																	A2($elm$html$Html$Attributes$style, 'margin', '0')
																]),
															A2($elm$core$List$concatMap, $terezka$elm_charts$Internal$Item$tooltip, barItems))
														]);
												}
											});
									}));
						}));
			});
		var forEachStackSeriesConfig = F3(
			function (bins, stackSeriesConfig, _v6) {
				var absoluteIndex = _v6.a;
				var stackSeriesConfigIndex = _v6.b;
				var _v7 = _v6.c;
				var limits = _v7.a;
				var items = _v7.b;
				var _v4 = $elm$core$List$unzip(
					function () {
						if (!stackSeriesConfig.$) {
							var barSeriesConfig = stackSeriesConfig.a;
							return _List_fromArray(
								[
									A6(forEachBarSeriesConfig, bins, absoluteIndex, stackSeriesConfigIndex, 1, 0, barSeriesConfig)
								]);
						} else {
							var barSeriesConfigs = stackSeriesConfig.a;
							var numOfBarsInStack = $elm$core$List$length(barSeriesConfigs);
							return A2(
								$elm$core$List$indexedMap,
								A4(forEachBarSeriesConfig, bins, absoluteIndex, stackSeriesConfigIndex, numOfBarsInStack),
								barSeriesConfigs);
						}
					}());
				var newLimits = _v4.a;
				var seriesItems = _v4.b;
				return _Utils_Tuple3(
					absoluteIndex + $elm$core$List$length(seriesItems),
					stackSeriesConfigIndex + 1,
					_Utils_Tuple2(
						_Utils_ap(
							limits,
							$elm$core$List$concat(newLimits)),
						F2(
							function (topLevel, localPlane) {
								return _Utils_ap(
									A2(items, topLevel, localPlane),
									A2(
										$elm$core$List$filterMap,
										$elm$core$Basics$identity,
										A2(
											$elm$core$List$map,
											function (i) {
												return A2(i, topLevel, localPlane);
											},
											seriesItems)));
							})));
			});
		return function (bins) {
			return function (_v2) {
				var newElementIndex = _v2.a;
				var _v3 = _v2.c;
				var limits = _v3.a;
				var items = _v3.b;
				return _Utils_Tuple3(newElementIndex, limits, items);
			}(
				A3(
					$elm$core$List$foldl,
					forEachStackSeriesConfig(bins),
					_Utils_Tuple3(
						elementIndex,
						0,
						_Utils_Tuple2(
							_List_Nil,
							F2(
								function (_v0, _v1) {
									return _List_Nil;
								}))),
					properties));
		}(
			A2(
				$terezka$elm_charts$Internal$Helpers$withSurround,
				data,
				$terezka$elm_charts$Internal$Produce$toBin(barsConfig)));
	});
var $terezka$elm_charts$Chart$barsMap = F4(
	function (mapData, edits, properties, data) {
		return $terezka$elm_charts$Chart$Indexed(
			F2(
				function (_v0, index) {
					var legends = A3($terezka$elm_charts$Internal$Legend$toBarLegends, index, edits, properties);
					var barsConfig = A2($terezka$elm_charts$Internal$Helpers$apply, edits, $terezka$elm_charts$Internal$Produce$defaultBars);
					var _v1 = A4($terezka$elm_charts$Internal$Produce$toBarSeries, index, edits, properties, data);
					var newElementIndex = _v1.a;
					var limits = _v1.b;
					var items = _v1.c;
					var toItems = F2(
						function (topLevel, localPlane) {
							return A2(
								$elm$core$List$concatMap,
								A2(
									$elm$core$Basics$composeR,
									$terezka$elm_charts$Internal$Many$getMembers,
									$elm$core$List$map(
										$terezka$elm_charts$Internal$Item$map(mapData))),
								A2(items, topLevel, localPlane));
						});
					var toTicks = F2(
						function (plane, acc) {
							return _Utils_update(
								acc,
								{
									S: _Utils_ap(
										acc.S,
										barsConfig.o ? A2(
											$elm$core$List$concatMap,
											function (limit) {
												return _List_fromArray(
													[limit.aX, limit.bi]);
											},
											limits) : _List_Nil)
								});
						});
					return _Utils_Tuple2(
						A5(
							$terezka$elm_charts$Chart$BarsElement,
							A2($terezka$elm_charts$Internal$Coordinates$foldPosition, $elm$core$Basics$identity, limits),
							toItems,
							legends,
							toTicks,
							F2(
								function (topLevel, plane) {
									return A2(
										$elm$svg$Svg$map,
										$elm$core$Basics$never,
										A2(
											$elm$svg$Svg$g,
											_List_fromArray(
												[
													$elm$svg$Svg$Attributes$class('elm-charts__bar-series')
												]),
											A2(
												$elm$core$List$map,
												$terezka$elm_charts$Internal$Item$render,
												A2(items, topLevel, plane))));
								})),
						newElementIndex);
				}));
	});
var $terezka$elm_charts$Chart$bars = F3(
	function (edits, properties, data) {
		return A4($terezka$elm_charts$Chart$barsMap, $elm$core$Basics$identity, edits, properties, data);
	});
var $terezka$elm_charts$Internal$Many$Remodel = F2(
	function (a, b) {
		return {$: 0, a: a, b: b};
	});
var $terezka$elm_charts$Internal$Many$andThen = F2(
	function (_v0, _v1) {
		var toPos2 = _v0.a;
		var func2 = _v0.b;
		var toPos1 = _v1.a;
		var func1 = _v1.b;
		return A2(
			$terezka$elm_charts$Internal$Many$Remodel,
			toPos2,
			function (items) {
				return func2(
					func1(items));
			});
	});
var $terezka$elm_charts$Chart$Item$andThen = $terezka$elm_charts$Internal$Many$andThen;
var $terezka$elm_charts$Internal$Item$getTopLevelPosition = function (_v0) {
	var item = _v0.b;
	return item.dM;
};
var $terezka$elm_charts$Internal$Item$isBar = function (_v0) {
	var meta = _v0.a;
	var item = _v0.b;
	var _v1 = meta.dN;
	if (_v1.$ === 1) {
		var bar = _v1.a;
		return $elm$core$Maybe$Just(
			A2(
				$terezka$elm_charts$Internal$Item$Rendered,
				{cc: meta.cc, dj: meta.dj, dw: meta.dw, dB: meta.dB, dH: meta.dH, dN: bar, d1: $terezka$elm_charts$Internal$Item$Bar, d7: meta.d7, aX: meta.aX, bi: meta.bi, c4: meta.c4},
				item));
	} else {
		return $elm$core$Maybe$Nothing;
	}
};
var $terezka$elm_charts$Internal$Many$bars = A2(
	$terezka$elm_charts$Internal$Many$Remodel,
	$terezka$elm_charts$Internal$Item$getTopLevelPosition,
	$elm$core$List$filterMap($terezka$elm_charts$Internal$Item$isBar));
var $terezka$elm_charts$Chart$Item$bars = $terezka$elm_charts$Internal$Many$bars;
var $terezka$elm_charts$Internal$Many$editLimits = F2(
	function (edit, _v0) {
		var _v1 = _v0.a;
		var x = _v1.a;
		var xs = _v1.b;
		var item = _v0.b;
		return A2(
			$terezka$elm_charts$Internal$Item$Rendered,
			_Utils_Tuple2(x, xs),
			_Utils_update(
				item,
				{
					I: A2(edit, x, item.I)
				}));
	});
var $terezka$elm_charts$Internal$Item$getX1 = function (_v0) {
	var meta = _v0.a;
	return meta.aX;
};
var $terezka$elm_charts$Internal$Item$getX2 = function (_v0) {
	var meta = _v0.a;
	return meta.bi;
};
var $elm$core$List$partition = F2(
	function (pred, list) {
		var step = F2(
			function (x, _v0) {
				var trues = _v0.a;
				var falses = _v0.b;
				return pred(x) ? _Utils_Tuple2(
					A2($elm$core$List$cons, x, trues),
					falses) : _Utils_Tuple2(
					trues,
					A2($elm$core$List$cons, x, falses));
			});
		return A3(
			$elm$core$List$foldr,
			step,
			_Utils_Tuple2(_List_Nil, _List_Nil),
			list);
	});
var $terezka$elm_charts$Internal$Helpers$gatherWith = F2(
	function (testFn, list) {
		var helper = F2(
			function (scattered, gathered) {
				if (!scattered.b) {
					return $elm$core$List$reverse(gathered);
				} else {
					var toGather = scattered.a;
					var population = scattered.b;
					var _v1 = A2(
						$elm$core$List$partition,
						testFn(toGather),
						population);
					var gathering = _v1.a;
					var remaining = _v1.b;
					return A2(
						helper,
						remaining,
						A2(
							$elm$core$List$cons,
							_Utils_Tuple2(toGather, gathering),
							gathered));
				}
			});
		return A2(helper, list, _List_Nil);
	});
var $terezka$elm_charts$Internal$Item$getTopLevelLimits = function (_v0) {
	var item = _v0.b;
	return item.dC;
};
var $terezka$elm_charts$Internal$Item$getTopLevelPlane = function (_v0) {
	var item = _v0.b;
	return item.dL;
};
var $terezka$elm_charts$Internal$Many$toGroup = F2(
	function (first, rest) {
		var plane = $terezka$elm_charts$Internal$Item$getTopLevelPlane(first);
		var all = A2($elm$core$List$cons, first, rest);
		var limits = A2($terezka$elm_charts$Internal$Coordinates$foldPosition, $terezka$elm_charts$Internal$Item$getTopLevelLimits, all);
		var position = A2($terezka$elm_charts$Internal$Coordinates$foldPosition, $terezka$elm_charts$Internal$Item$getTopLevelPosition, all);
		return A2(
			$terezka$elm_charts$Internal$Item$Rendered,
			_Utils_Tuple2(first, rest),
			{
				I: limits,
				dC: limits,
				dD: plane,
				dL: plane,
				F: position,
				dM: position,
				cL: function (_v0) {
					return A2(
						$elm$svg$Svg$g,
						_List_fromArray(
							[
								$elm$svg$Svg$Attributes$class('elm-charts__group')
							]),
						A2($elm$core$List$map, $terezka$elm_charts$Internal$Item$render, all));
				},
				d6: function (c) {
					return _List_fromArray(
						[
							A2(
							$elm$html$Html$table,
							_List_Nil,
							A2($elm$core$List$concatMap, $terezka$elm_charts$Internal$Item$tooltip, all))
						]);
				}
			});
	});
var $terezka$elm_charts$Internal$Many$groupingHelp = F2(
	function (_v0, items) {
		var shared = _v0.bt;
		var equality = _v0.bo;
		var edits = _v0.bn;
		var toShared = function (_v2) {
			var meta = _v2.a;
			var item = _v2.b;
			return shared(meta);
		};
		var toNewGroup = function (_v1) {
			var i = _v1.a;
			var is = _v1.b;
			return edits(
				A2($terezka$elm_charts$Internal$Many$toGroup, i, is));
		};
		var toEquality = F2(
			function (aO, bO) {
				return A2(
					equality,
					toShared(aO),
					toShared(bO));
			});
		return A2(
			$elm$core$List$map,
			toNewGroup,
			A2($terezka$elm_charts$Internal$Helpers$gatherWith, toEquality, items));
	});
var $terezka$elm_charts$Internal$Many$bins = A2(
	$terezka$elm_charts$Internal$Many$Remodel,
	$terezka$elm_charts$Internal$Item$getPosition,
	$terezka$elm_charts$Internal$Many$groupingHelp(
		{
			bn: $terezka$elm_charts$Internal$Many$editLimits(
				F2(
					function (item, pos) {
						return _Utils_update(
							pos,
							{
								aX: $terezka$elm_charts$Internal$Item$getX1(item),
								bi: $terezka$elm_charts$Internal$Item$getX2(item)
							});
					})),
			bo: F2(
				function (a, b) {
					return _Utils_eq(a.aX, b.aX) && (_Utils_eq(a.bi, b.bi) && (_Utils_eq(a.bA, b.bA) && _Utils_eq(a.cd, b.cd)));
				}),
			bt: function (config) {
				return {cd: config.dw.cd, bA: config.dw.$7, aX: config.aX, bi: config.bi};
			}
		}));
var $terezka$elm_charts$Chart$Item$bins = $terezka$elm_charts$Internal$Many$bins;
var $terezka$elm_charts$Internal$Svg$defaultLabel = {u: $elm$core$Maybe$Nothing, g: _List_Nil, N: 'white', T: 0, cc: '#808BAB', v: $elm$core$Maybe$Nothing, w: $elm$core$Maybe$Nothing, x: false, B: 0, D: false, p: 0, q: 0};
var $terezka$elm_charts$Internal$Coordinates$bottom = function (pos) {
	return {c3: pos.aX + ((pos.bi - pos.aX) / 2), c4: pos.ee};
};
var $terezka$elm_charts$Internal$Item$getPositionIn = F2(
	function (plane, _v0) {
		var item = _v0.b;
		return A3($terezka$elm_charts$Internal$Coordinates$convertPos, plane, item.dD, item.F);
	});
var $terezka$elm_charts$Chart$Item$getBottom = function (p) {
	return A2(
		$elm$core$Basics$composeR,
		$terezka$elm_charts$Internal$Item$getPositionIn(p),
		$terezka$elm_charts$Internal$Coordinates$bottom);
};
var $terezka$elm_charts$Chart$defaultLabel = {u: $terezka$elm_charts$Internal$Svg$defaultLabel.u, g: $terezka$elm_charts$Internal$Svg$defaultLabel.g, N: $terezka$elm_charts$Internal$Svg$defaultLabel.N, T: $terezka$elm_charts$Internal$Svg$defaultLabel.T, cc: $terezka$elm_charts$Internal$Svg$defaultLabel.cc, v: $terezka$elm_charts$Internal$Svg$defaultLabel.v, w: $terezka$elm_charts$Internal$Svg$defaultLabel.w, O: $elm$core$Maybe$Nothing, x: $terezka$elm_charts$Internal$Svg$defaultLabel.x, F: $terezka$elm_charts$Chart$Item$getBottom, B: $terezka$elm_charts$Internal$Svg$defaultLabel.B, D: $terezka$elm_charts$Internal$Svg$defaultLabel.D, p: $terezka$elm_charts$Internal$Svg$defaultLabel.p, q: $terezka$elm_charts$Internal$Svg$defaultLabel.q};
var $terezka$elm_charts$Chart$SubElements = function (a) {
	return {$: 10, a: a};
};
var $terezka$elm_charts$Internal$Many$apply = F2(
	function (_v0, items) {
		var func = _v0.b;
		return func(items);
	});
var $terezka$elm_charts$Chart$Item$apply = $terezka$elm_charts$Internal$Many$apply;
var $terezka$elm_charts$Chart$eachCustom = F2(
	function (grouping, func) {
		return $terezka$elm_charts$Chart$SubElements(
			F2(
				function (p, items) {
					var processed = A2($terezka$elm_charts$Chart$Item$apply, grouping, items);
					return A2(
						$elm$core$List$concatMap,
						func(p),
						processed);
				}));
	});
var $terezka$elm_charts$Internal$Item$getDatum = function (_v0) {
	var meta = _v0.a;
	return meta.dj;
};
var $terezka$elm_charts$Internal$Many$getData = function (_v0) {
	var _v1 = _v0.a;
	var x = _v1.a;
	var xs = _v1.b;
	return $terezka$elm_charts$Internal$Item$getDatum(x);
};
var $terezka$elm_charts$Chart$Item$getOneData = $terezka$elm_charts$Internal$Many$getData;
var $elm$svg$Svg$foreignObject = $elm$svg$Svg$trustedNode('foreignObject');
var $elm$svg$Svg$Attributes$transform = _VirtualDom_attribute('transform');
var $terezka$elm_charts$Internal$Svg$position = F6(
	function (plane, rotation, x_, y_, xOff_, yOff_) {
		return $elm$svg$Svg$Attributes$transform(
			'translate(' + ($elm$core$String$fromFloat(
				A2($terezka$elm_charts$Internal$Coordinates$toSVGX, plane, x_) + xOff_) + (',' + ($elm$core$String$fromFloat(
				A2($terezka$elm_charts$Internal$Coordinates$toSVGY, plane, y_) + yOff_) + (') rotate(' + ($elm$core$String$fromFloat(rotation) + ')'))))));
	});
var $elm$svg$Svg$Attributes$style = _VirtualDom_attribute('style');
var $elm$svg$Svg$text_ = $elm$svg$Svg$trustedNode('text');
var $elm$svg$Svg$tspan = $elm$svg$Svg$trustedNode('tspan');
var $terezka$elm_charts$Internal$Svg$label = F4(
	function (plane, config, inner, point) {
		var _v0 = config.v;
		if (_v0.$ === 1) {
			var withOverflowWrap = function (el) {
				return config.x ? A2(
					$elm$svg$Svg$g,
					_List_fromArray(
						[
							$terezka$elm_charts$Internal$Svg$withinChartArea(plane)
						]),
					_List_fromArray(
						[el])) : el;
			};
			var uppercaseStyle = config.D ? 'text-transform: uppercase;' : '';
			var fontStyle = function () {
				var _v5 = config.w;
				if (!_v5.$) {
					var size_ = _v5.a;
					return 'font-size: ' + ($elm$core$String$fromInt(size_) + 'px;');
				} else {
					return '';
				}
			}();
			var anchorStyle = function () {
				var _v1 = config.u;
				if (_v1.$ === 1) {
					return 'text-anchor: middle;';
				} else {
					switch (_v1.a) {
						case 0:
							var _v2 = _v1.a;
							return 'text-anchor: end;';
						case 1:
							var _v3 = _v1.a;
							return 'text-anchor: start;';
						default:
							var _v4 = _v1.a;
							return 'text-anchor: middle;';
					}
				}
			}();
			return withOverflowWrap(
				A4(
					$terezka$elm_charts$Internal$Svg$withAttrs,
					config.g,
					$elm$svg$Svg$text_,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$class('elm-charts__label'),
							$elm$svg$Svg$Attributes$stroke(config.N),
							$elm$svg$Svg$Attributes$strokeWidth(
							$elm$core$String$fromFloat(config.T)),
							$elm$svg$Svg$Attributes$fill(config.cc),
							A6($terezka$elm_charts$Internal$Svg$position, plane, -config.B, point.c3, point.c4, config.p, config.q),
							$elm$svg$Svg$Attributes$style(
							A2(
								$elm$core$String$join,
								' ',
								_List_fromArray(
									['pointer-events: none;', fontStyle, anchorStyle, uppercaseStyle])))
						]),
					_List_fromArray(
						[
							A2($elm$svg$Svg$tspan, _List_Nil, inner)
						])));
		} else {
			var ellipsis = _v0.a;
			var xOffWithAnchor = function () {
				var _v11 = config.u;
				if (_v11.$ === 1) {
					return config.p - (ellipsis.c2 / 2);
				} else {
					switch (_v11.a) {
						case 0:
							var _v12 = _v11.a;
							return config.p - ellipsis.c2;
						case 1:
							var _v13 = _v11.a;
							return config.p;
						default:
							var _v14 = _v11.a;
							return config.p - (ellipsis.c2 / 2);
					}
				}
			}();
			var withOverflowWrap = function (el) {
				return config.x ? A2(
					$elm$svg$Svg$g,
					_List_fromArray(
						[
							$terezka$elm_charts$Internal$Svg$withinChartArea(plane)
						]),
					_List_fromArray(
						[el])) : el;
			};
			var uppercaseStyle = config.D ? A2($elm$html$Html$Attributes$style, 'text-transform', 'uppercase') : A2($elm$html$Html$Attributes$style, '', '');
			var fontStyle = function () {
				var _v10 = config.w;
				if (!_v10.$) {
					var size_ = _v10.a;
					return A2(
						$elm$html$Html$Attributes$style,
						'font-size',
						$elm$core$String$fromInt(size_) + 'px');
				} else {
					return A2($elm$html$Html$Attributes$style, '', '');
				}
			}();
			var anchorStyle = function () {
				var _v6 = config.u;
				if (_v6.$ === 1) {
					return A2($elm$html$Html$Attributes$style, 'text-align', 'center');
				} else {
					switch (_v6.a) {
						case 0:
							var _v7 = _v6.a;
							return A2($elm$html$Html$Attributes$style, 'text-align', 'right');
						case 1:
							var _v8 = _v6.a;
							return A2($elm$html$Html$Attributes$style, 'text-align', 'left');
						default:
							var _v9 = _v6.a;
							return A2($elm$html$Html$Attributes$style, 'text-align', 'center');
					}
				}
			}();
			return withOverflowWrap(
				A4(
					$terezka$elm_charts$Internal$Svg$withAttrs,
					config.g,
					$elm$svg$Svg$foreignObject,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$class('elm-charts__label'),
							$elm$svg$Svg$Attributes$class('elm-charts__html-label'),
							$elm$svg$Svg$Attributes$width(
							$elm$core$String$fromFloat(ellipsis.c2)),
							$elm$svg$Svg$Attributes$height(
							$elm$core$String$fromFloat(ellipsis.cq)),
							A6($terezka$elm_charts$Internal$Svg$position, plane, -config.B, point.c3, point.c4, xOffWithAnchor, config.q - 10)
						]),
					_List_fromArray(
						[
							A2(
							$elm$html$Html$div,
							_List_fromArray(
								[
									A2($elm$html$Html$Attributes$attribute, 'xmlns', 'http://www.w3.org/1999/xhtml'),
									A2($elm$html$Html$Attributes$style, 'white-space', 'nowrap'),
									A2($elm$html$Html$Attributes$style, 'overflow', 'hidden'),
									A2($elm$html$Html$Attributes$style, 'text-overflow', 'ellipsis'),
									A2($elm$html$Html$Attributes$style, 'height', '100%'),
									A2($elm$html$Html$Attributes$style, 'pointer-events', 'none'),
									A2($elm$html$Html$Attributes$style, 'color', config.cc),
									fontStyle,
									uppercaseStyle,
									anchorStyle
								]),
							inner)
						])));
		}
	});
var $terezka$elm_charts$Chart$SvgElement = function (a) {
	return {$: 13, a: a};
};
var $terezka$elm_charts$Chart$svg = function (func) {
	return $terezka$elm_charts$Chart$SvgElement(
		function (p) {
			return func(p);
		});
};
var $elm$svg$Svg$text = $elm$virtual_dom$VirtualDom$text;
var $terezka$elm_charts$Chart$toLabelFromItemLabel = function (config) {
	return {u: config.u, g: config.g, N: config.N, T: config.T, cc: config.cc, v: config.v, w: config.w, x: config.x, B: config.B, D: config.D, p: config.p, q: config.q};
};
var $terezka$elm_charts$Chart$binLabels = F2(
	function (toLabel, edits) {
		return A2(
			$terezka$elm_charts$Chart$eachCustom,
			A2($terezka$elm_charts$Chart$Item$andThen, $terezka$elm_charts$Chart$Item$bins, $terezka$elm_charts$Chart$Item$bars),
			F2(
				function (p, item) {
					var config = A2($terezka$elm_charts$Internal$Helpers$apply, edits, $terezka$elm_charts$Chart$defaultLabel);
					var text = function () {
						var _v1 = config.O;
						if (!_v1.$) {
							var formatting = _v1.a;
							return formatting(item);
						} else {
							return toLabel(
								$terezka$elm_charts$Chart$Item$getOneData(item));
						}
					}();
					return _List_fromArray(
						[
							$terezka$elm_charts$Chart$svg(
							function (_v0) {
								return A4(
									$terezka$elm_charts$Internal$Svg$label,
									p,
									$terezka$elm_charts$Chart$toLabelFromItemLabel(config),
									_List_fromArray(
										[
											$elm$svg$Svg$text(text)
										]),
									A2(config.F, p, item));
							})
						]);
				}));
	});
var $terezka$elm_charts$Internal$Svg$Event = F2(
	function (name, handler) {
		return {co: handler, dH: name};
	});
var $terezka$elm_charts$Chart$GridElement = function (a) {
	return {$: 9, a: a};
};
var $terezka$elm_charts$Internal$Svg$Circle = 0;
var $terezka$elm_charts$Chart$Attributes$circle = function (config) {
	return _Utils_update(
		config,
		{
			aR: $elm$core$Maybe$Just(0)
		});
};
var $terezka$elm_charts$Internal$Helpers$darkGray = 'rgb(200 200 200)';
var $terezka$elm_charts$Chart$Attributes$dashed = function (value) {
	return function (config) {
		return _Utils_update(
			config,
			{bl: value});
	};
};
var $terezka$elm_charts$Internal$Svg$defaultDot = {N: '', dd: 1, T: 0, cc: $terezka$elm_charts$Internal$Helpers$pink, x: false, dt: 0, du: '', dv: 5, am: 1, aR: $elm$core$Maybe$Nothing, cU: 6};
var $terezka$elm_charts$Internal$Svg$isWithinPlane = F3(
	function (plane, x, y) {
		return _Utils_eq(
			A3($elm$core$Basics$clamp, plane.c3.aa, plane.c3.Q, x),
			x) && _Utils_eq(
			A3($elm$core$Basics$clamp, plane.c4.aa, plane.c4.Q, y),
			y);
	});
var $elm$core$Basics$pi = _Basics_pi;
var $elm$core$Basics$sqrt = _Basics_sqrt;
var $terezka$elm_charts$Internal$Svg$plusPath = F4(
	function (area_, off, x_, y_) {
		var side = $elm$core$Basics$sqrt(area_ / 4) + off;
		var r6 = side / 2;
		var r3 = side;
		return A2(
			$elm$core$String$join,
			' ',
			_List_fromArray(
				[
					'M' + ($elm$core$String$fromFloat(x_ - r6) + (' ' + $elm$core$String$fromFloat(((y_ - r3) - r6) + off))),
					'v' + $elm$core$String$fromFloat(r3 - off),
					'h' + $elm$core$String$fromFloat((-r3) + off),
					'v' + $elm$core$String$fromFloat(r3),
					'h' + $elm$core$String$fromFloat(r3 - off),
					'v' + $elm$core$String$fromFloat(r3 - off),
					'h' + $elm$core$String$fromFloat(r3),
					'v' + $elm$core$String$fromFloat((-r3) + off),
					'h' + $elm$core$String$fromFloat(r3 - off),
					'v' + $elm$core$String$fromFloat(-r3),
					'h' + $elm$core$String$fromFloat((-r3) + off),
					'v' + $elm$core$String$fromFloat((-r3) + off),
					'h' + $elm$core$String$fromFloat(-r3),
					'v' + $elm$core$String$fromFloat(r3 - off)
				]));
	});
var $elm$svg$Svg$rect = $elm$svg$Svg$trustedNode('rect');
var $elm$core$Basics$degrees = function (angleInDegrees) {
	return (angleInDegrees * $elm$core$Basics$pi) / 180;
};
var $elm$core$Basics$tan = _Basics_tan;
var $terezka$elm_charts$Internal$Svg$trianglePath = F4(
	function (area_, off, x_, y_) {
		var side = $elm$core$Basics$sqrt(
			(area_ * 4) / $elm$core$Basics$sqrt(3)) + (off * $elm$core$Basics$sqrt(3));
		var height = ($elm$core$Basics$sqrt(3) * side) / 2;
		var fromMiddle = height - (($elm$core$Basics$tan(
			$elm$core$Basics$degrees(30)) * side) / 2);
		return A2(
			$elm$core$String$join,
			' ',
			_List_fromArray(
				[
					'M' + ($elm$core$String$fromFloat(x_) + (' ' + $elm$core$String$fromFloat(y_ - fromMiddle))),
					'l' + ($elm$core$String$fromFloat((-side) / 2) + (' ' + $elm$core$String$fromFloat(height))),
					'h' + $elm$core$String$fromFloat(side),
					'z'
				]));
	});
var $elm$svg$Svg$Attributes$x = _VirtualDom_attribute('x');
var $terezka$elm_charts$Internal$Svg$dot = F5(
	function (plane, toX, toY, config, datum_) {
		var yOrg = toY(datum_);
		var y_ = A2($terezka$elm_charts$Internal$Coordinates$toSVGY, plane, yOrg);
		var xOrg = toX(datum_);
		var x_ = A2($terezka$elm_charts$Internal$Coordinates$toSVGX, plane, xOrg);
		var styleAttrs = _List_fromArray(
			[
				$elm$svg$Svg$Attributes$stroke(
				(config.N === '') ? config.cc : config.N),
				$elm$svg$Svg$Attributes$strokeWidth(
				$elm$core$String$fromFloat(config.T)),
				$elm$svg$Svg$Attributes$strokeOpacity(
				$elm$core$String$fromFloat(config.dd)),
				$elm$svg$Svg$Attributes$fillOpacity(
				$elm$core$String$fromFloat(config.am)),
				$elm$svg$Svg$Attributes$fill(config.cc),
				$elm$svg$Svg$Attributes$class('elm-charts__dot'),
				config.x ? $terezka$elm_charts$Internal$Svg$withinChartArea(plane) : $elm$svg$Svg$Attributes$class('')
			]);
		var showDot = A3($terezka$elm_charts$Internal$Svg$isWithinPlane, plane, xOrg, yOrg) || config.x;
		var highlightColor = (config.du === '') ? config.cc : config.du;
		var highlightAttrs = _List_fromArray(
			[
				$elm$svg$Svg$Attributes$stroke(highlightColor),
				$elm$svg$Svg$Attributes$strokeWidth(
				$elm$core$String$fromFloat(config.dv)),
				$elm$svg$Svg$Attributes$strokeOpacity(
				$elm$core$String$fromFloat(config.dt)),
				$elm$svg$Svg$Attributes$fill('transparent'),
				$elm$svg$Svg$Attributes$class('elm-charts__dot-highlight')
			]);
		var view = F3(
			function (toEl, highlightOff, toAttrs) {
				return (config.dt > 0) ? A2(
					$elm$svg$Svg$g,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$class('elm-charts__dot-container')
						]),
					_List_fromArray(
						[
							A2(
							toEl,
							_Utils_ap(
								toAttrs(highlightOff),
								highlightAttrs),
							_List_Nil),
							A2(
							toEl,
							_Utils_ap(
								toAttrs(0),
								styleAttrs),
							_List_Nil)
						])) : A2(
					toEl,
					_Utils_ap(
						toAttrs(0),
						styleAttrs),
					_List_Nil);
			});
		var area_ = (2 * $elm$core$Basics$pi) * config.cU;
		if (!showDot) {
			return $elm$svg$Svg$text('');
		} else {
			var _v0 = config.aR;
			if (_v0.$ === 1) {
				return $elm$svg$Svg$text('');
			} else {
				switch (_v0.a) {
					case 0:
						var _v1 = _v0.a;
						return A3(
							view,
							$elm$svg$Svg$circle,
							config.dv / 2,
							function (off) {
								var radius = $elm$core$Basics$sqrt(area_ / $elm$core$Basics$pi);
								return _List_fromArray(
									[
										$elm$svg$Svg$Attributes$cx(
										$elm$core$String$fromFloat(x_)),
										$elm$svg$Svg$Attributes$cy(
										$elm$core$String$fromFloat(y_)),
										$elm$svg$Svg$Attributes$r(
										$elm$core$String$fromFloat(radius + off))
									]);
							});
					case 1:
						var _v2 = _v0.a;
						return A3(
							view,
							$elm$svg$Svg$path,
							config.dv,
							function (off) {
								return _List_fromArray(
									[
										$elm$svg$Svg$Attributes$d(
										A4($terezka$elm_charts$Internal$Svg$trianglePath, area_, off, x_, y_))
									]);
							});
					case 2:
						var _v3 = _v0.a;
						return A3(
							view,
							$elm$svg$Svg$rect,
							config.dv,
							function (off) {
								var side = $elm$core$Basics$sqrt(area_);
								var sideOff = side + off;
								return _List_fromArray(
									[
										$elm$svg$Svg$Attributes$x(
										$elm$core$String$fromFloat(x_ - (sideOff / 2))),
										$elm$svg$Svg$Attributes$y(
										$elm$core$String$fromFloat(y_ - (sideOff / 2))),
										$elm$svg$Svg$Attributes$width(
										$elm$core$String$fromFloat(sideOff)),
										$elm$svg$Svg$Attributes$height(
										$elm$core$String$fromFloat(sideOff))
									]);
							});
					case 3:
						var _v4 = _v0.a;
						return A3(
							view,
							$elm$svg$Svg$rect,
							config.dv,
							function (off) {
								var side = $elm$core$Basics$sqrt(area_);
								var sideOff = side + off;
								return _List_fromArray(
									[
										$elm$svg$Svg$Attributes$x(
										$elm$core$String$fromFloat(x_ - (sideOff / 2))),
										$elm$svg$Svg$Attributes$y(
										$elm$core$String$fromFloat(y_ - (sideOff / 2))),
										$elm$svg$Svg$Attributes$width(
										$elm$core$String$fromFloat(sideOff)),
										$elm$svg$Svg$Attributes$height(
										$elm$core$String$fromFloat(sideOff)),
										$elm$svg$Svg$Attributes$transform(
										'rotate(45 ' + ($elm$core$String$fromFloat(x_) + (' ' + ($elm$core$String$fromFloat(y_) + ')'))))
									]);
							});
					case 4:
						var _v5 = _v0.a;
						return A3(
							view,
							$elm$svg$Svg$path,
							config.dv,
							function (off) {
								return _List_fromArray(
									[
										$elm$svg$Svg$Attributes$d(
										A4($terezka$elm_charts$Internal$Svg$plusPath, area_, off, x_, y_)),
										$elm$svg$Svg$Attributes$transform(
										'rotate(45 ' + ($elm$core$String$fromFloat(x_) + (' ' + ($elm$core$String$fromFloat(y_) + ')'))))
									]);
							});
					default:
						var _v6 = _v0.a;
						return A3(
							view,
							$elm$svg$Svg$path,
							config.dv,
							function (off) {
								return _List_fromArray(
									[
										$elm$svg$Svg$Attributes$d(
										A4($terezka$elm_charts$Internal$Svg$plusPath, area_, off, x_, y_))
									]);
							});
				}
			}
		}
	});
var $terezka$elm_charts$Chart$Svg$dot = F4(
	function (plane, toX, toY, edits) {
		return A4(
			$terezka$elm_charts$Internal$Svg$dot,
			plane,
			toX,
			toY,
			A2($terezka$elm_charts$Internal$Helpers$apply, edits, $terezka$elm_charts$Internal$Svg$defaultDot));
	});
var $terezka$elm_charts$Internal$Helpers$gray = '#EFF2FA';
var $terezka$elm_charts$Internal$Svg$defaultLine = {g: _List_Nil, de: false, cc: 'rgb(210, 210, 210)', bl: _List_Nil, f: false, x: false, am: 1, dY: -90, dZ: 0, c2: 1, aX: $elm$core$Maybe$Nothing, bi: $elm$core$Maybe$Nothing, ed: $elm$core$Maybe$Nothing, p: 0, ee: $elm$core$Maybe$Nothing, b5: $elm$core$Maybe$Nothing, ef: $elm$core$Maybe$Nothing, q: 0};
var $elm$core$Basics$cos = _Basics_cos;
var $terezka$elm_charts$Internal$Svg$lengthInCartesianX = $terezka$elm_charts$Internal$Coordinates$scaleCartesianX;
var $terezka$elm_charts$Internal$Svg$lengthInCartesianY = $terezka$elm_charts$Internal$Coordinates$scaleCartesianY;
var $elm$core$Basics$sin = _Basics_sin;
var $elm$svg$Svg$Attributes$strokeDasharray = _VirtualDom_attribute('stroke-dasharray');
var $terezka$elm_charts$Internal$Svg$line = F2(
	function (plane, config) {
		var angle = $elm$core$Basics$degrees(config.dY);
		var _v0 = function () {
			var _v3 = _Utils_Tuple3(
				_Utils_Tuple2(config.aX, config.bi),
				_Utils_Tuple2(config.ee, config.b5),
				_Utils_Tuple2(config.ed, config.ef));
			if (!_v3.a.a.$) {
				if (!_v3.a.b.$) {
					if (_v3.b.a.$ === 1) {
						if (_v3.b.b.$ === 1) {
							var _v4 = _v3.a;
							var a = _v4.a.a;
							var b = _v4.b.a;
							var _v5 = _v3.b;
							var _v6 = _v5.a;
							var _v7 = _v5.b;
							return _Utils_Tuple2(
								_Utils_Tuple2(a, b),
								_Utils_Tuple2(plane.c4.aa, plane.c4.aa));
						} else {
							var _v38 = _v3.a;
							var a = _v38.a.a;
							var b = _v38.b.a;
							var _v39 = _v3.b;
							var _v40 = _v39.a;
							var c = _v39.b.a;
							return _Utils_Tuple2(
								_Utils_Tuple2(a, b),
								_Utils_Tuple2(c, c));
						}
					} else {
						if (_v3.b.b.$ === 1) {
							var _v41 = _v3.a;
							var a = _v41.a.a;
							var b = _v41.b.a;
							var _v42 = _v3.b;
							var c = _v42.a.a;
							var _v43 = _v42.b;
							return _Utils_Tuple2(
								_Utils_Tuple2(a, b),
								_Utils_Tuple2(c, c));
						} else {
							return _Utils_Tuple2(
								_Utils_Tuple2(
									A2($elm$core$Maybe$withDefault, plane.c3.aa, config.aX),
									A2($elm$core$Maybe$withDefault, plane.c3.Q, config.bi)),
								_Utils_Tuple2(
									A2($elm$core$Maybe$withDefault, plane.c4.aa, config.ee),
									A2($elm$core$Maybe$withDefault, plane.c4.Q, config.b5)));
						}
					}
				} else {
					if (_v3.b.a.$ === 1) {
						if (_v3.b.b.$ === 1) {
							var _v8 = _v3.a;
							var a = _v8.a.a;
							var _v9 = _v8.b;
							var _v10 = _v3.b;
							var _v11 = _v10.a;
							var _v12 = _v10.b;
							return _Utils_Tuple2(
								_Utils_Tuple2(a, a),
								_Utils_Tuple2(plane.c4.aa, plane.c4.Q));
						} else {
							if (!_v3.c.a.$) {
								if (!_v3.c.b.$) {
									var _v51 = _v3.a;
									var a = _v51.a.a;
									var _v52 = _v51.b;
									var _v53 = _v3.b;
									var _v54 = _v53.a;
									var b = _v53.b.a;
									var _v55 = _v3.c;
									var xOff = _v55.a.a;
									var yOff = _v55.b.a;
									return _Utils_Tuple2(
										_Utils_Tuple2(
											a,
											a + A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianX, plane, xOff)),
										_Utils_Tuple2(
											b,
											b + A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianY, plane, yOff)));
								} else {
									var _v56 = _v3.a;
									var a = _v56.a.a;
									var _v57 = _v56.b;
									var _v58 = _v3.b;
									var _v59 = _v58.a;
									var b = _v58.b.a;
									var _v60 = _v3.c;
									var xOff = _v60.a.a;
									var _v61 = _v60.b;
									return _Utils_Tuple2(
										_Utils_Tuple2(
											a,
											a + A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianX, plane, xOff)),
										_Utils_Tuple2(b, b));
								}
							} else {
								if (_v3.c.b.$ === 1) {
									var _v44 = _v3.a;
									var a = _v44.a.a;
									var _v45 = _v44.b;
									var _v46 = _v3.b;
									var _v47 = _v46.a;
									var b = _v46.b.a;
									var _v48 = _v3.c;
									var _v49 = _v48.a;
									var _v50 = _v48.b;
									return _Utils_Tuple2(
										_Utils_Tuple2(a, plane.c3.Q),
										_Utils_Tuple2(b, b));
								} else {
									var _v62 = _v3.a;
									var a = _v62.a.a;
									var _v63 = _v62.b;
									var _v64 = _v3.b;
									var _v65 = _v64.a;
									var b = _v64.b.a;
									var _v66 = _v3.c;
									var _v67 = _v66.a;
									var yOff = _v66.b.a;
									return _Utils_Tuple2(
										_Utils_Tuple2(a, a),
										_Utils_Tuple2(
											b,
											b + A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianY, plane, yOff)));
								}
							}
						}
					} else {
						if (!_v3.b.b.$) {
							var _v35 = _v3.a;
							var c = _v35.a.a;
							var _v36 = _v35.b;
							var _v37 = _v3.b;
							var a = _v37.a.a;
							var b = _v37.b.a;
							return _Utils_Tuple2(
								_Utils_Tuple2(c, c),
								_Utils_Tuple2(a, b));
						} else {
							if (!_v3.c.a.$) {
								if (!_v3.c.b.$) {
									var _v75 = _v3.a;
									var a = _v75.a.a;
									var _v76 = _v75.b;
									var _v77 = _v3.b;
									var b = _v77.a.a;
									var _v78 = _v77.b;
									var _v79 = _v3.c;
									var xOff = _v79.a.a;
									var yOff = _v79.b.a;
									return _Utils_Tuple2(
										_Utils_Tuple2(
											a,
											a + A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianX, plane, xOff)),
										_Utils_Tuple2(
											b,
											b + A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianY, plane, yOff)));
								} else {
									var _v80 = _v3.a;
									var a = _v80.a.a;
									var _v81 = _v80.b;
									var _v82 = _v3.b;
									var b = _v82.a.a;
									var _v83 = _v82.b;
									var _v84 = _v3.c;
									var xOff = _v84.a.a;
									var _v85 = _v84.b;
									return _Utils_Tuple2(
										_Utils_Tuple2(
											a,
											a + A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianX, plane, xOff)),
										_Utils_Tuple2(b, b));
								}
							} else {
								if (_v3.c.b.$ === 1) {
									var _v68 = _v3.a;
									var a = _v68.a.a;
									var _v69 = _v68.b;
									var _v70 = _v3.b;
									var b = _v70.a.a;
									var _v71 = _v70.b;
									var _v72 = _v3.c;
									var _v73 = _v72.a;
									var _v74 = _v72.b;
									return _Utils_Tuple2(
										_Utils_Tuple2(a, plane.c3.Q),
										_Utils_Tuple2(b, b));
								} else {
									var _v86 = _v3.a;
									var a = _v86.a.a;
									var _v87 = _v86.b;
									var _v88 = _v3.b;
									var b = _v88.a.a;
									var _v89 = _v88.b;
									var _v90 = _v3.c;
									var _v91 = _v90.a;
									var yOff = _v90.b.a;
									return _Utils_Tuple2(
										_Utils_Tuple2(a, a),
										_Utils_Tuple2(
											b,
											b + A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianY, plane, yOff)));
								}
							}
						}
					}
				}
			} else {
				if (!_v3.a.b.$) {
					if (_v3.b.a.$ === 1) {
						if (_v3.b.b.$ === 1) {
							var _v13 = _v3.a;
							var _v14 = _v13.a;
							var b = _v13.b.a;
							var _v15 = _v3.b;
							var _v16 = _v15.a;
							var _v17 = _v15.b;
							return _Utils_Tuple2(
								_Utils_Tuple2(b, b),
								_Utils_Tuple2(plane.c4.aa, plane.c4.Q));
						} else {
							if (!_v3.c.a.$) {
								if (!_v3.c.b.$) {
									var _v99 = _v3.a;
									var _v100 = _v99.a;
									var a = _v99.b.a;
									var _v101 = _v3.b;
									var _v102 = _v101.a;
									var b = _v101.b.a;
									var _v103 = _v3.c;
									var xOff = _v103.a.a;
									var yOff = _v103.b.a;
									return _Utils_Tuple2(
										_Utils_Tuple2(
											a,
											a + A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianX, plane, xOff)),
										_Utils_Tuple2(
											b,
											b + A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianY, plane, yOff)));
								} else {
									var _v104 = _v3.a;
									var _v105 = _v104.a;
									var a = _v104.b.a;
									var _v106 = _v3.b;
									var _v107 = _v106.a;
									var b = _v106.b.a;
									var _v108 = _v3.c;
									var xOff = _v108.a.a;
									var _v109 = _v108.b;
									return _Utils_Tuple2(
										_Utils_Tuple2(
											a,
											a + A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianX, plane, xOff)),
										_Utils_Tuple2(b, b));
								}
							} else {
								if (_v3.c.b.$ === 1) {
									var _v92 = _v3.a;
									var _v93 = _v92.a;
									var a = _v92.b.a;
									var _v94 = _v3.b;
									var _v95 = _v94.a;
									var b = _v94.b.a;
									var _v96 = _v3.c;
									var _v97 = _v96.a;
									var _v98 = _v96.b;
									return _Utils_Tuple2(
										_Utils_Tuple2(a, plane.c3.Q),
										_Utils_Tuple2(b, b));
								} else {
									var _v110 = _v3.a;
									var _v111 = _v110.a;
									var a = _v110.b.a;
									var _v112 = _v3.b;
									var _v113 = _v112.a;
									var b = _v112.b.a;
									var _v114 = _v3.c;
									var _v115 = _v114.a;
									var yOff = _v114.b.a;
									return _Utils_Tuple2(
										_Utils_Tuple2(a, a),
										_Utils_Tuple2(
											b,
											b + A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianY, plane, yOff)));
								}
							}
						}
					} else {
						if (!_v3.b.b.$) {
							var _v32 = _v3.a;
							var _v33 = _v32.a;
							var c = _v32.b.a;
							var _v34 = _v3.b;
							var a = _v34.a.a;
							var b = _v34.b.a;
							return _Utils_Tuple2(
								_Utils_Tuple2(c, c),
								_Utils_Tuple2(a, b));
						} else {
							if (!_v3.c.a.$) {
								if (!_v3.c.b.$) {
									var _v123 = _v3.a;
									var _v124 = _v123.a;
									var a = _v123.b.a;
									var _v125 = _v3.b;
									var b = _v125.a.a;
									var _v126 = _v125.b;
									var _v127 = _v3.c;
									var xOff = _v127.a.a;
									var yOff = _v127.b.a;
									return _Utils_Tuple2(
										_Utils_Tuple2(
											a,
											a + A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianX, plane, xOff)),
										_Utils_Tuple2(
											b,
											b + A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianY, plane, yOff)));
								} else {
									var _v128 = _v3.a;
									var _v129 = _v128.a;
									var a = _v128.b.a;
									var _v130 = _v3.b;
									var b = _v130.a.a;
									var _v131 = _v130.b;
									var _v132 = _v3.c;
									var xOff = _v132.a.a;
									var _v133 = _v132.b;
									return _Utils_Tuple2(
										_Utils_Tuple2(
											a,
											a + A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianX, plane, xOff)),
										_Utils_Tuple2(b, b));
								}
							} else {
								if (_v3.c.b.$ === 1) {
									var _v116 = _v3.a;
									var _v117 = _v116.a;
									var a = _v116.b.a;
									var _v118 = _v3.b;
									var b = _v118.a.a;
									var _v119 = _v118.b;
									var _v120 = _v3.c;
									var _v121 = _v120.a;
									var _v122 = _v120.b;
									return _Utils_Tuple2(
										_Utils_Tuple2(a, plane.c3.Q),
										_Utils_Tuple2(b, b));
								} else {
									var _v134 = _v3.a;
									var _v135 = _v134.a;
									var a = _v134.b.a;
									var _v136 = _v3.b;
									var b = _v136.a.a;
									var _v137 = _v136.b;
									var _v138 = _v3.c;
									var _v139 = _v138.a;
									var yOff = _v138.b.a;
									return _Utils_Tuple2(
										_Utils_Tuple2(a, a),
										_Utils_Tuple2(
											b,
											b + A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianY, plane, yOff)));
								}
							}
						}
					}
				} else {
					if (!_v3.b.a.$) {
						if (!_v3.b.b.$) {
							var _v18 = _v3.a;
							var _v19 = _v18.a;
							var _v20 = _v18.b;
							var _v21 = _v3.b;
							var a = _v21.a.a;
							var b = _v21.b.a;
							return _Utils_Tuple2(
								_Utils_Tuple2(plane.c3.aa, plane.c3.aa),
								_Utils_Tuple2(a, b));
						} else {
							var _v22 = _v3.a;
							var _v23 = _v22.a;
							var _v24 = _v22.b;
							var _v25 = _v3.b;
							var a = _v25.a.a;
							var _v26 = _v25.b;
							return _Utils_Tuple2(
								_Utils_Tuple2(plane.c3.aa, plane.c3.Q),
								_Utils_Tuple2(a, a));
						}
					} else {
						if (!_v3.b.b.$) {
							var _v27 = _v3.a;
							var _v28 = _v27.a;
							var _v29 = _v27.b;
							var _v30 = _v3.b;
							var _v31 = _v30.a;
							var b = _v30.b.a;
							return _Utils_Tuple2(
								_Utils_Tuple2(plane.c3.aa, plane.c3.Q),
								_Utils_Tuple2(b, b));
						} else {
							var _v140 = _v3.a;
							var _v141 = _v140.a;
							var _v142 = _v140.b;
							var _v143 = _v3.b;
							var _v144 = _v143.a;
							var _v145 = _v143.b;
							return _Utils_Tuple2(
								_Utils_Tuple2(plane.c3.aa, plane.c3.Q),
								_Utils_Tuple2(plane.c4.aa, plane.c4.Q));
						}
					}
				}
			}
		}();
		var _v1 = _v0.a;
		var x1 = _v1.a;
		var x2 = _v1.b;
		var _v2 = _v0.b;
		var y1 = _v2.a;
		var y2 = _v2.b;
		var x1_ = x1 + A2($terezka$elm_charts$Internal$Svg$lengthInCartesianX, plane, config.p);
		var x2_ = x2 + A2($terezka$elm_charts$Internal$Svg$lengthInCartesianX, plane, config.p);
		var y1_ = y1 - A2($terezka$elm_charts$Internal$Svg$lengthInCartesianY, plane, config.q);
		var y2_ = y2 - A2($terezka$elm_charts$Internal$Svg$lengthInCartesianY, plane, config.q);
		var _v146 = (config.dZ > 0) ? _Utils_Tuple2(
			A2(
				$terezka$elm_charts$Internal$Svg$lengthInCartesianX,
				plane,
				$elm$core$Basics$cos(angle) * config.dZ),
			A2(
				$terezka$elm_charts$Internal$Svg$lengthInCartesianY,
				plane,
				$elm$core$Basics$sin(angle) * config.dZ)) : _Utils_Tuple2(0, 0);
		var tickOffsetX = _v146.a;
		var tickOffsetY = _v146.b;
		var cmds = config.f ? _Utils_ap(
			(config.dZ > 0) ? _List_fromArray(
				[
					A2($terezka$elm_charts$Internal$Commands$Move, x2_ + tickOffsetX, y2_ + tickOffsetY),
					A2($terezka$elm_charts$Internal$Commands$Line, x2_, y2_)
				]) : _List_fromArray(
				[
					A2($terezka$elm_charts$Internal$Commands$Move, x2_, y2_)
				]),
			_Utils_ap(
				config.de ? _List_fromArray(
					[
						A2($terezka$elm_charts$Internal$Commands$Line, x2_, y1_),
						A2($terezka$elm_charts$Internal$Commands$Line, x1_, y1_)
					]) : _List_fromArray(
					[
						A2($terezka$elm_charts$Internal$Commands$Line, x1_, y1_)
					]),
				(config.dZ > 0) ? _List_fromArray(
					[
						A2($terezka$elm_charts$Internal$Commands$Line, x1_ + tickOffsetX, y1_ + tickOffsetY)
					]) : _List_Nil)) : _Utils_ap(
			(config.dZ > 0) ? _List_fromArray(
				[
					A2($terezka$elm_charts$Internal$Commands$Move, x1_ + tickOffsetX, y1_ + tickOffsetY),
					A2($terezka$elm_charts$Internal$Commands$Line, x1_, y1_)
				]) : _List_fromArray(
				[
					A2($terezka$elm_charts$Internal$Commands$Move, x1_, y1_)
				]),
			_Utils_ap(
				config.de ? _List_fromArray(
					[
						A2($terezka$elm_charts$Internal$Commands$Line, x1_, y2_),
						A2($terezka$elm_charts$Internal$Commands$Line, x2_, y2_)
					]) : _List_fromArray(
					[
						A2($terezka$elm_charts$Internal$Commands$Line, x2_, y2_)
					]),
				(config.dZ > 0) ? _List_fromArray(
					[
						A2($terezka$elm_charts$Internal$Commands$Line, x2_ + tickOffsetX, y2_ + tickOffsetY)
					]) : _List_Nil));
		return A4(
			$terezka$elm_charts$Internal$Svg$withAttrs,
			config.g,
			$elm$svg$Svg$path,
			_List_fromArray(
				[
					$elm$svg$Svg$Attributes$class('elm-charts__line'),
					$elm$svg$Svg$Attributes$fill('transparent'),
					$elm$svg$Svg$Attributes$stroke(config.cc),
					$elm$svg$Svg$Attributes$strokeWidth(
					$elm$core$String$fromFloat(config.c2)),
					$elm$svg$Svg$Attributes$strokeOpacity(
					$elm$core$String$fromFloat(config.am)),
					$elm$svg$Svg$Attributes$strokeDasharray(
					A2(
						$elm$core$String$join,
						' ',
						A2($elm$core$List$map, $elm$core$String$fromFloat, config.bl))),
					$elm$svg$Svg$Attributes$d(
					A2($terezka$elm_charts$Internal$Commands$description, plane, cmds)),
					config.x ? $terezka$elm_charts$Internal$Svg$withinChartArea(plane) : $elm$svg$Svg$Attributes$class('')
				]),
			_List_Nil);
	});
var $terezka$elm_charts$Chart$Svg$line = F2(
	function (plane, edits) {
		return A2(
			$terezka$elm_charts$Internal$Svg$line,
			plane,
			A2($terezka$elm_charts$Internal$Helpers$apply, edits, $terezka$elm_charts$Internal$Svg$defaultLine));
	});
var $terezka$elm_charts$Chart$Attributes$size = function (v) {
	return function (config) {
		return _Utils_update(
			config,
			{cU: v});
	};
};
var $terezka$elm_charts$Chart$Attributes$width = function (v) {
	return function (config) {
		return _Utils_update(
			config,
			{c2: v});
	};
};
var $terezka$elm_charts$Chart$Attributes$x1 = function (v) {
	return function (config) {
		return _Utils_update(
			config,
			{
				aX: $elm$core$Maybe$Just(v)
			});
	};
};
var $terezka$elm_charts$Chart$Attributes$y1 = function (v) {
	return function (config) {
		return _Utils_update(
			config,
			{
				ee: $elm$core$Maybe$Just(v)
			});
	};
};
var $terezka$elm_charts$Chart$grid = function (edits) {
	var config = A2(
		$terezka$elm_charts$Internal$Helpers$apply,
		edits,
		{cc: '', bl: _List_Nil, a$: false, c2: 0});
	var width = (!config.c2) ? (config.a$ ? 0.5 : 1) : config.c2;
	var color = $elm$core$String$isEmpty(config.cc) ? (config.a$ ? $terezka$elm_charts$Internal$Helpers$darkGray : $terezka$elm_charts$Internal$Helpers$gray) : config.cc;
	var toDot = F4(
		function (vs, p, x, y) {
			return (A2($elm$core$List$member, x, vs.bj) || A2($elm$core$List$member, y, vs.bk)) ? $elm$core$Maybe$Nothing : $elm$core$Maybe$Just(
				A5(
					$terezka$elm_charts$Chart$Svg$dot,
					p,
					function ($) {
						return $.c3;
					},
					function ($) {
						return $.c4;
					},
					_List_fromArray(
						[
							$terezka$elm_charts$Chart$Attributes$color(color),
							$terezka$elm_charts$Chart$Attributes$size(width),
							$terezka$elm_charts$Chart$Attributes$circle
						]),
					{c3: x, c4: y}));
		});
	var toXGrid = F3(
		function (vs, p, v) {
			return A2($elm$core$List$member, v, vs.bj) ? $elm$core$Maybe$Nothing : $elm$core$Maybe$Just(
				A2(
					$terezka$elm_charts$Chart$Svg$line,
					p,
					_List_fromArray(
						[
							$terezka$elm_charts$Chart$Attributes$color(color),
							$terezka$elm_charts$Chart$Attributes$width(width),
							$terezka$elm_charts$Chart$Attributes$x1(v),
							$terezka$elm_charts$Chart$Attributes$dashed(config.bl)
						])));
		});
	var toYGrid = F3(
		function (vs, p, v) {
			return A2($elm$core$List$member, v, vs.bk) ? $elm$core$Maybe$Nothing : $elm$core$Maybe$Just(
				A2(
					$terezka$elm_charts$Chart$Svg$line,
					p,
					_List_fromArray(
						[
							$terezka$elm_charts$Chart$Attributes$color(color),
							$terezka$elm_charts$Chart$Attributes$width(width),
							$terezka$elm_charts$Chart$Attributes$y1(v),
							$terezka$elm_charts$Chart$Attributes$dashed(config.bl)
						])));
		});
	return $terezka$elm_charts$Chart$GridElement(
		F2(
			function (p, vs) {
				return A2(
					$elm$svg$Svg$g,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$class('elm-charts__grid')
						]),
					config.a$ ? A2(
						$elm$core$List$concatMap,
						function (x) {
							return A2(
								$elm$core$List$filterMap,
								A3(toDot, vs, p, x),
								vs.ad);
						},
						vs.S) : _List_fromArray(
						[
							A2(
							$elm$svg$Svg$g,
							_List_fromArray(
								[
									$elm$svg$Svg$Attributes$class('elm-charts__x-grid')
								]),
							A2(
								$elm$core$List$filterMap,
								A2(toXGrid, vs, p),
								vs.S)),
							A2(
							$elm$svg$Svg$g,
							_List_fromArray(
								[
									$elm$svg$Svg$Attributes$class('elm-charts__y-grid')
								]),
							A2(
								$elm$core$List$filterMap,
								A2(toYGrid, vs, p),
								vs.ad))
						]));
			}));
};
var $terezka$elm_charts$Chart$addGridIfNone = function (elements) {
	var isGrid = function (el) {
		if (el.$ === 9) {
			return true;
		} else {
			return false;
		}
	};
	return A2($elm$core$List$any, isGrid, elements) ? elements : A2(
		$elm$core$List$cons,
		$terezka$elm_charts$Chart$grid(_List_Nil),
		elements);
};
var $terezka$elm_charts$Chart$addIndexes = F2(
	function (planeConfig, startIndex) {
		var toIndexedElements = F2(
			function (element, _v0) {
				var allElements = _v0.a;
				var index = _v0.b;
				switch (element.$) {
					case 0:
						var func = element.a;
						var _v2 = A2(func, planeConfig, index);
						var indexedElement = _v2.a;
						var nextIndex = _v2.b;
						return _Utils_Tuple2(
							_Utils_ap(
								allElements,
								_List_fromArray(
									[indexedElement])),
							nextIndex);
					case 11:
						var elements = element.a;
						return A3(
							$elm$core$List$foldl,
							toIndexedElements,
							_Utils_Tuple2(allElements, index),
							elements);
					default:
						return _Utils_Tuple2(
							_Utils_ap(
								allElements,
								_List_fromArray(
									[element])),
							index);
				}
			});
		return A2(
			$elm$core$List$foldl,
			toIndexedElements,
			_Utils_Tuple2(_List_Nil, startIndex));
	});
var $elm$svg$Svg$clipPath = $elm$svg$Svg$trustedNode('clipPath');
var $elm$json$Json$Decode$map3 = _Json_map3;
var $K_Adam$elm_dom$DOM$offsetHeight = A2($elm$json$Json$Decode$field, 'offsetHeight', $elm$json$Json$Decode$float);
var $K_Adam$elm_dom$DOM$offsetWidth = A2($elm$json$Json$Decode$field, 'offsetWidth', $elm$json$Json$Decode$float);
var $elm$json$Json$Decode$map4 = _Json_map4;
var $K_Adam$elm_dom$DOM$offsetLeft = A2($elm$json$Json$Decode$field, 'offsetLeft', $elm$json$Json$Decode$float);
var $K_Adam$elm_dom$DOM$offsetParent = F2(
	function (x, decoder) {
		return $elm$json$Json$Decode$oneOf(
			_List_fromArray(
				[
					A2(
					$elm$json$Json$Decode$field,
					'offsetParent',
					$elm$json$Json$Decode$null(x)),
					A2($elm$json$Json$Decode$field, 'offsetParent', decoder)
				]));
	});
var $K_Adam$elm_dom$DOM$offsetTop = A2($elm$json$Json$Decode$field, 'offsetTop', $elm$json$Json$Decode$float);
var $K_Adam$elm_dom$DOM$scrollLeft = A2($elm$json$Json$Decode$field, 'scrollLeft', $elm$json$Json$Decode$float);
var $K_Adam$elm_dom$DOM$scrollTop = A2($elm$json$Json$Decode$field, 'scrollTop', $elm$json$Json$Decode$float);
var $K_Adam$elm_dom$DOM$position = F2(
	function (x, y) {
		return A2(
			$elm$json$Json$Decode$andThen,
			function (_v0) {
				var x_ = _v0.a;
				var y_ = _v0.b;
				return A2(
					$K_Adam$elm_dom$DOM$offsetParent,
					_Utils_Tuple2(x_, y_),
					A2($K_Adam$elm_dom$DOM$position, x_, y_));
			},
			A5(
				$elm$json$Json$Decode$map4,
				F4(
					function (scrollLeftP, scrollTopP, offsetLeftP, offsetTopP) {
						return _Utils_Tuple2((x + offsetLeftP) - scrollLeftP, (y + offsetTopP) - scrollTopP);
					}),
				$K_Adam$elm_dom$DOM$scrollLeft,
				$K_Adam$elm_dom$DOM$scrollTop,
				$K_Adam$elm_dom$DOM$offsetLeft,
				$K_Adam$elm_dom$DOM$offsetTop));
	});
var $K_Adam$elm_dom$DOM$boundingClientRect = A4(
	$elm$json$Json$Decode$map3,
	F3(
		function (_v0, width, height) {
			var x = _v0.a;
			var y = _v0.b;
			return {cq: height, bJ: x, b3: y, c2: width};
		}),
	A2($K_Adam$elm_dom$DOM$position, 0, 0),
	$K_Adam$elm_dom$DOM$offsetWidth,
	$K_Adam$elm_dom$DOM$offsetHeight);
var $elm$json$Json$Decode$lazy = function (thunk) {
	return A2(
		$elm$json$Json$Decode$andThen,
		thunk,
		$elm$json$Json$Decode$succeed(0));
};
var $K_Adam$elm_dom$DOM$parentElement = function (decoder) {
	return A2($elm$json$Json$Decode$field, 'parentElement', decoder);
};
function $terezka$elm_charts$Internal$Svg$cyclic$decodePosition() {
	return $elm$json$Json$Decode$oneOf(
		_List_fromArray(
			[
				$K_Adam$elm_dom$DOM$boundingClientRect,
				$elm$json$Json$Decode$lazy(
				function (_v0) {
					return $K_Adam$elm_dom$DOM$parentElement(
						$terezka$elm_charts$Internal$Svg$cyclic$decodePosition());
				})
			]));
}
var $terezka$elm_charts$Internal$Svg$decodePosition = $terezka$elm_charts$Internal$Svg$cyclic$decodePosition();
$terezka$elm_charts$Internal$Svg$cyclic$decodePosition = function () {
	return $terezka$elm_charts$Internal$Svg$decodePosition;
};
var $terezka$elm_charts$Internal$Coordinates$toCartesianX = F2(
	function (plane, value) {
		return plane.c3.f ? (($terezka$elm_charts$Internal$Coordinates$range(plane.c3) - A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianX, plane, value - plane.c3.dF)) + plane.c3.aa) : (A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianX, plane, value - plane.c3.dF) + plane.c3.aa);
	});
var $terezka$elm_charts$Internal$Coordinates$toCartesianY = F2(
	function (plane, value) {
		return plane.c4.f ? (A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianY, plane, value - plane.c4.dF) + plane.c4.aa) : (($terezka$elm_charts$Internal$Coordinates$range(plane.c4) - A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianY, plane, value - plane.c4.dF)) + plane.c4.aa);
	});
var $terezka$elm_charts$Internal$Svg$fromSvg = F2(
	function (plane, point) {
		return {
			c3: A2($terezka$elm_charts$Internal$Coordinates$toCartesianX, plane, point.c3),
			c4: A2($terezka$elm_charts$Internal$Coordinates$toCartesianY, plane, point.c4)
		};
	});
var $K_Adam$elm_dom$DOM$target = function (decoder) {
	return A2($elm$json$Json$Decode$field, 'target', decoder);
};
var $terezka$elm_charts$Internal$Svg$decoder = F2(
	function (plane, toMsg) {
		var handle = F3(
			function (mouseX, mouseY, box) {
				var yPrev = plane.c4;
				var xPrev = plane.c3;
				var widthPercent = box.c2 / plane.c3.ak;
				var heightPercent = box.cq / plane.c4.ak;
				var newPlane = _Utils_update(
					plane,
					{
						c3: _Utils_update(
							xPrev,
							{ak: box.c2, dE: plane.c3.dE * widthPercent, dF: plane.c3.dF * widthPercent}),
						c4: _Utils_update(
							yPrev,
							{ak: box.cq, dE: plane.c4.dE * heightPercent, dF: plane.c4.dF * heightPercent})
					});
				var searched = A2(
					$terezka$elm_charts$Internal$Svg$fromSvg,
					newPlane,
					{c3: mouseX - box.bJ, c4: mouseY - box.b3});
				return A3(toMsg, plane, newPlane, searched);
			});
		return A4(
			$elm$json$Json$Decode$map3,
			handle,
			A2($elm$json$Json$Decode$field, 'pageX', $elm$json$Json$Decode$float),
			A2($elm$json$Json$Decode$field, 'pageY', $elm$json$Json$Decode$float),
			$K_Adam$elm_dom$DOM$target($terezka$elm_charts$Internal$Svg$decodePosition));
	});
var $elm$svg$Svg$Events$on = $elm$html$Html$Events$on;
var $elm$svg$Svg$svg = $elm$svg$Svg$trustedNode('svg');
var $elm$svg$Svg$Attributes$viewBox = _VirtualDom_attribute('viewBox');
var $terezka$elm_charts$Internal$Svg$container = F5(
	function (plane, config, below, chartEls, above) {
		var toEvent = function (event) {
			return A2(
				$elm$svg$Svg$Events$on,
				event.dH,
				A2($terezka$elm_charts$Internal$Svg$decoder, plane, event.co));
		};
		var svgAttrsSize = function () {
			var _v0 = config.c$;
			if (!_v0.$) {
				var viewport = _v0.a;
				return _List_fromArray(
					[
						$elm$svg$Svg$Attributes$viewBox(
						'0 0 ' + ($elm$core$String$fromInt(viewport.c2) + (' ' + $elm$core$String$fromInt(viewport.cq)))),
						A2($elm$html$Html$Attributes$style, 'display', 'block')
					]);
			} else {
				return _List_fromArray(
					[
						$elm$svg$Svg$Attributes$viewBox(
						'0 0 ' + ($elm$core$String$fromFloat(plane.c3.ak) + (' ' + $elm$core$String$fromFloat(plane.c4.ak)))),
						A2($elm$html$Html$Attributes$style, 'display', 'block')
					]);
			}
		}();
		var htmlAttrsSize = _List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'width', '100%'),
				A2($elm$html$Html$Attributes$style, 'height', '100%')
			]);
		var htmlAttrsDefault = _List_fromArray(
			[
				$elm$html$Html$Attributes$class('elm-charts__container-inner')
			]);
		var htmlAttrs = _Utils_ap(
			htmlAttrsDefault,
			_Utils_ap(htmlAttrsSize, config.bq));
		var chartPosition = _List_fromArray(
			[
				$elm$svg$Svg$Attributes$x(
				$elm$core$String$fromFloat(plane.c3.dF)),
				$elm$svg$Svg$Attributes$y(
				$elm$core$String$fromFloat(plane.c4.dF)),
				$elm$svg$Svg$Attributes$width(
				$elm$core$String$fromFloat(
					$terezka$elm_charts$Internal$Coordinates$innerWidth(plane))),
				$elm$svg$Svg$Attributes$height(
				$elm$core$String$fromFloat(
					$terezka$elm_charts$Internal$Coordinates$innerHeight(plane))),
				$elm$svg$Svg$Attributes$fill('transparent')
			]);
		var clipPathDefs = A2(
			$elm$svg$Svg$defs,
			_List_Nil,
			_List_fromArray(
				[
					A2(
					$elm$svg$Svg$clipPath,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$id(
							$terezka$elm_charts$Internal$Coordinates$toId(plane))
						]),
					_List_fromArray(
						[
							A2($elm$svg$Svg$rect, chartPosition, _List_Nil)
						]))
				]));
		var catcher = A2(
			$elm$svg$Svg$rect,
			_Utils_ap(
				chartPosition,
				A2($elm$core$List$map, toEvent, config.bp)),
			_List_Nil);
		var chart = A2(
			$elm$svg$Svg$svg,
			_Utils_ap(svgAttrsSize, config.g),
			_Utils_ap(
				_List_fromArray(
					[clipPathDefs]),
				_Utils_ap(
					chartEls,
					_List_fromArray(
						[catcher]))));
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('elm-charts__container'),
					A2($elm$html$Html$Attributes$style, 'position', 'relative')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$div,
					htmlAttrs,
					_Utils_ap(
						below,
						_Utils_ap(
							_List_fromArray(
								[chart]),
							above)))
				]));
	});
var $terezka$elm_charts$Chart$Attributes$lowest = F2(
	function (v, edit) {
		return function (b) {
			return _Utils_update(
				b,
				{
					aa: A3(edit, v, b.aa, b.di)
				});
		};
	});
var $terezka$elm_charts$Chart$Attributes$orLower = F3(
	function (least, real, _v0) {
		return (_Utils_cmp(real, least) > 0) ? least : real;
	});
var $terezka$elm_charts$Chart$definePlane = F2(
	function (config, elements) {
		var width = A2($elm$core$Basics$max, 1, (config.c2 - config.z.bJ) - config.z.bT);
		var toLimit = F5(
			function (length, marginMin, marginMax, min, max) {
				return {dh: max, di: min, f: false, ak: length, dE: marginMax, dF: marginMin, Q: max, aa: min};
			});
		var height = A2($elm$core$Basics$max, 1, (config.cq - config.z.bx) - config.z.b3);
		var fixSingles = function (bs) {
			return _Utils_eq(bs.aa, bs.Q) ? _Utils_update(
				bs,
				{Q: bs.aa + 10}) : bs;
		};
		var collectLimits = F2(
			function (el, acc) {
				switch (el.$) {
					case 0:
						return acc;
					case 1:
						var lims = el.a;
						return _Utils_ap(
							acc,
							_List_fromArray(
								[lims]));
					case 2:
						var lims = el.a;
						return _Utils_ap(
							acc,
							_List_fromArray(
								[lims]));
					case 3:
						var lims = el.a;
						return _Utils_ap(
							acc,
							_List_fromArray(
								[lims]));
					case 4:
						return acc;
					case 5:
						return acc;
					case 6:
						return acc;
					case 7:
						return acc;
					case 8:
						return acc;
					case 9:
						return acc;
					case 10:
						return acc;
					case 11:
						var subs = el.a;
						return A3($elm$core$List$foldl, collectLimits, acc, subs);
					case 12:
						return acc;
					case 13:
						return acc;
					default:
						return acc;
				}
			});
		var limits_ = function (pos) {
			return function (_v5) {
				var x = _v5.c3;
				var y = _v5.c4;
				return {
					c3: fixSingles(x),
					c4: fixSingles(y)
				};
			}(
				{
					c3: A5(toLimit, width, config.X.bJ, config.X.bT, pos.aX, pos.bi),
					c4: A5(toLimit, height, config.X.b3, config.X.bx, pos.ee, pos.b5)
				});
		}(
			A2(
				$terezka$elm_charts$Internal$Coordinates$foldPosition,
				$elm$core$Basics$identity,
				A3($elm$core$List$foldl, collectLimits, _List_Nil, elements)));
		var calcRange = function () {
			var _v4 = config.ao;
			if (!_v4.b) {
				return limits_.c3;
			} else {
				var some = _v4;
				return A2($terezka$elm_charts$Internal$Helpers$apply, some, limits_.c3);
			}
		}();
		var calcDomain = function () {
			var _v3 = config.ah;
			if (!_v3.b) {
				return A2(
					$terezka$elm_charts$Internal$Helpers$apply,
					_List_fromArray(
						[
							A2($terezka$elm_charts$Chart$Attributes$lowest, 0, $terezka$elm_charts$Chart$Attributes$orLower)
						]),
					limits_.c4);
			} else {
				var some = _v3;
				return A2($terezka$elm_charts$Internal$Helpers$apply, some, limits_.c4);
			}
		}();
		var unpadded = {c3: calcRange, c4: calcDomain};
		var scalePadX = $terezka$elm_charts$Internal$Coordinates$scaleCartesianX(unpadded);
		var xMax = calcRange.Q + scalePadX(
			calcRange.f ? config.z.bJ : config.z.bT);
		var xMin = calcRange.aa - scalePadX(
			calcRange.f ? config.z.bT : config.z.bJ);
		var scalePadY = $terezka$elm_charts$Internal$Coordinates$scaleCartesianY(unpadded);
		var yMax = calcDomain.Q + scalePadY(
			calcDomain.f ? config.z.bx : config.z.b3);
		var yMin = calcDomain.aa - scalePadY(
			calcDomain.f ? config.z.b3 : config.z.bx);
		var _v1 = function () {
			var _v2 = config.c$;
			if (!_v2.$) {
				var vp = _v2.a;
				return _Utils_Tuple2(vp.c2 / config.c2, vp.cq / config.cq);
			} else {
				return _Utils_Tuple2(1, 1);
			}
		}();
		var ratioX = _v1.a;
		var ratioY = _v1.b;
		return {
			c3: _Utils_update(
				calcRange,
				{
					ak: config.c2 * ratioX,
					Q: A2($elm$core$Basics$max, xMin, xMax),
					aa: A2($elm$core$Basics$min, xMin, xMax)
				}),
			c4: _Utils_update(
				calcDomain,
				{
					ak: config.cq * ratioY,
					Q: A2($elm$core$Basics$max, yMin, yMax),
					aa: A2($elm$core$Basics$min, yMin, yMax)
				})
		};
	});
var $terezka$elm_charts$Chart$getItems = F3(
	function (topLevel, plane, elements) {
		var toItems = F2(
			function (el, acc) {
				switch (el.$) {
					case 0:
						return acc;
					case 1:
						var item = el.b;
						return _Utils_ap(
							acc,
							A2(item, topLevel, plane));
					case 2:
						var item = el.b;
						return _Utils_ap(
							acc,
							A2(item, topLevel, plane));
					case 3:
						var item = el.b;
						return _Utils_ap(
							acc,
							_List_fromArray(
								[
									A2(item, topLevel, plane)
								]));
					case 4:
						var func = el.a;
						return acc;
					case 5:
						return acc;
					case 6:
						return acc;
					case 7:
						return acc;
					case 8:
						return acc;
					case 9:
						return acc;
					case 10:
						return acc;
					case 11:
						var subs = el.a;
						return A3($elm$core$List$foldl, toItems, acc, subs);
					case 12:
						var items = el.b;
						return _Utils_ap(
							acc,
							items(topLevel));
					case 13:
						return acc;
					default:
						return acc;
				}
			});
		return A3($elm$core$List$foldl, toItems, _List_Nil, elements);
	});
var $terezka$elm_charts$Chart$getLegends = function (elements) {
	var toLegends = F2(
		function (el, acc) {
			switch (el.$) {
				case 0:
					return acc;
				case 1:
					var legends = el.c;
					return _Utils_ap(acc, legends);
				case 2:
					var legends = el.c;
					return _Utils_ap(acc, legends);
				case 3:
					return acc;
				case 4:
					return acc;
				case 5:
					return acc;
				case 6:
					return acc;
				case 7:
					return acc;
				case 8:
					return acc;
				case 9:
					return acc;
				case 10:
					return acc;
				case 11:
					var subs = el.a;
					return A3($elm$core$List$foldl, toLegends, acc, subs);
				case 12:
					var legends = el.c;
					return _Utils_ap(acc, legends);
				case 13:
					return acc;
				default:
					return acc;
			}
		});
	return A3($elm$core$List$foldl, toLegends, _List_Nil, elements);
};
var $terezka$elm_charts$Chart$TickValues = F4(
	function (xAxis, yAxis, xs, ys) {
		return {bj: xAxis, S: xs, bk: yAxis, ad: ys};
	});
var $terezka$elm_charts$Chart$getTickValues = F3(
	function (plane, items, elements) {
		var toValues = F2(
			function (el, acc) {
				switch (el.$) {
					case 0:
						return acc;
					case 1:
						return acc;
					case 2:
						var func = el.d;
						return A2(func, plane, acc);
					case 3:
						return acc;
					case 4:
						var func = el.a;
						return A2(func, plane, acc);
					case 5:
						var func = el.a;
						return A2(func, plane, acc);
					case 6:
						var toC = el.a;
						var func = el.b;
						return A3(
							func,
							plane,
							toC(plane),
							acc);
					case 7:
						var toC = el.a;
						var func = el.b;
						return A3(
							func,
							plane,
							toC(plane),
							acc);
					case 8:
						var toC = el.a;
						var func = el.b;
						return A3(
							func,
							plane,
							toC(plane),
							acc);
					case 10:
						var func = el.a;
						return A3(
							$elm$core$List$foldl,
							toValues,
							acc,
							A2(func, plane, items));
					case 9:
						return acc;
					case 11:
						var subs = el.a;
						return A3($elm$core$List$foldl, toValues, acc, subs);
					case 12:
						return acc;
					case 13:
						return acc;
					default:
						return acc;
				}
			});
		return A3(
			$elm$core$List$foldl,
			toValues,
			A4($terezka$elm_charts$Chart$TickValues, _List_Nil, _List_Nil, _List_Nil, _List_Nil),
			elements);
	});
var $terezka$elm_charts$Chart$viewElements = F6(
	function (topLevel, plane, tickValues, allItems, allLegends, elements) {
		var viewOne = F2(
			function (el, _v0) {
				var before = _v0.a;
				var chart_ = _v0.b;
				var after = _v0.c;
				switch (el.$) {
					case 0:
						return _Utils_Tuple3(before, chart_, after);
					case 1:
						var view = el.d;
						return _Utils_Tuple3(
							before,
							A2(
								$elm$core$List$cons,
								A2(view, topLevel, plane),
								chart_),
							after);
					case 2:
						var view = el.e;
						return _Utils_Tuple3(
							before,
							A2(
								$elm$core$List$cons,
								A2(view, topLevel, plane),
								chart_),
							after);
					case 3:
						var view = el.c;
						return _Utils_Tuple3(
							before,
							A2(
								$elm$core$List$cons,
								A2(view, topLevel, plane),
								chart_),
							after);
					case 4:
						var view = el.b;
						return _Utils_Tuple3(
							before,
							A2(
								$elm$core$List$cons,
								view(plane),
								chart_),
							after);
					case 5:
						var view = el.b;
						return _Utils_Tuple3(
							before,
							A2(
								$elm$core$List$cons,
								view(plane),
								chart_),
							after);
					case 6:
						var toC = el.a;
						var view = el.c;
						return _Utils_Tuple3(
							before,
							A2(
								$elm$core$List$cons,
								A2(
									view,
									plane,
									toC(plane)),
								chart_),
							after);
					case 7:
						var toC = el.a;
						var view = el.c;
						return _Utils_Tuple3(
							before,
							A2(
								$elm$core$List$cons,
								A2(
									view,
									plane,
									toC(plane)),
								chart_),
							after);
					case 8:
						var toC = el.a;
						var view = el.c;
						return _Utils_Tuple3(
							before,
							A2(
								$elm$core$List$cons,
								A2(
									view,
									plane,
									toC(plane)),
								chart_),
							after);
					case 9:
						var view = el.a;
						return _Utils_Tuple3(
							before,
							A2(
								$elm$core$List$cons,
								A2(view, plane, tickValues),
								chart_),
							after);
					case 10:
						var func = el.a;
						return A3(
							$elm$core$List$foldr,
							viewOne,
							_Utils_Tuple3(before, chart_, after),
							A2(func, plane, allItems));
					case 11:
						var els = el.a;
						return A3(
							$elm$core$List$foldr,
							viewOne,
							_Utils_Tuple3(before, chart_, after),
							els);
					case 12:
						var view = el.d;
						return function (_v2) {
							var b = _v2.a;
							var c = _v2.b;
							var e = _v2.c;
							return _Utils_Tuple3(
								_Utils_ap(b, before),
								_Utils_ap(c, chart_),
								_Utils_ap(e, after));
						}(
							view(topLevel));
					case 13:
						var view = el.a;
						return _Utils_Tuple3(
							before,
							A2(
								$elm$core$List$cons,
								view(plane),
								chart_),
							after);
					default:
						var view = el.a;
						return _Utils_Tuple3(
							($elm$core$List$length(chart_) > 0) ? A2(
								$elm$core$List$cons,
								A2(view, plane, allLegends),
								before) : before,
							chart_,
							($elm$core$List$length(chart_) > 0) ? after : A2(
								$elm$core$List$cons,
								A2(view, plane, allLegends),
								after));
				}
			});
		return A3(
			$elm$core$List$foldr,
			viewOne,
			_Utils_Tuple3(_List_Nil, _List_Nil, _List_Nil),
			elements);
	});
var $terezka$elm_charts$Chart$chartAndPlane = F2(
	function (edits, unindexedElements) {
		var config = A2(
			$terezka$elm_charts$Internal$Helpers$apply,
			edits,
			{
				g: _List_fromArray(
					[
						$elm$svg$Svg$Attributes$style('overflow: visible;')
					]),
				ah: _List_Nil,
				bp: _List_Nil,
				cq: 300,
				bq: _List_Nil,
				X: {bx: 0, bJ: 0, bT: 0, b3: 0},
				z: {bx: 0, bJ: 0, bT: 0, b3: 0},
				ao: _List_Nil,
				c$: $elm$core$Maybe$Nothing,
				c2: 300
			});
		var planeConfig = {ah: config.ah, cq: config.cq, X: config.X, z: config.z, ao: config.ao, c$: config.c$, c2: config.c2};
		var _v0 = A3($terezka$elm_charts$Chart$addIndexes, planeConfig, 0, unindexedElements);
		var indexedElements = _v0.a;
		var elements = $terezka$elm_charts$Chart$addGridIfNone(indexedElements);
		var legends = $terezka$elm_charts$Chart$getLegends(elements);
		var plane = A2($terezka$elm_charts$Chart$definePlane, planeConfig, elements);
		var items = A3($terezka$elm_charts$Chart$getItems, plane, plane, elements);
		var toEvent = function (_v3) {
			var event_ = _v3;
			var _v2 = event_.dk;
			var decoder = _v2;
			return A2(
				$terezka$elm_charts$Internal$Svg$Event,
				event_.dH,
				decoder(items));
		};
		var tickValues = A3($terezka$elm_charts$Chart$getTickValues, plane, items, elements);
		var _v1 = A6($terezka$elm_charts$Chart$viewElements, plane, plane, tickValues, items, legends, elements);
		var beforeEls = _v1.a;
		var chartEls = _v1.b;
		var afterEls = _v1.c;
		return _Utils_Tuple2(
			A5(
				$terezka$elm_charts$Internal$Svg$container,
				plane,
				{
					g: config.g,
					bp: A2($elm$core$List$map, toEvent, config.bp),
					bq: config.bq,
					c$: config.c$
				},
				beforeEls,
				chartEls,
				afterEls),
			plane);
	});
var $terezka$elm_charts$Chart$chart = F2(
	function (edits, unindexedElements) {
		return A2($terezka$elm_charts$Chart$chartAndPlane, edits, unindexedElements).a;
	});
var $terezka$elm_charts$Chart$Attributes$fontSize = function (v) {
	return function (config) {
		return _Utils_update(
			config,
			{
				w: $elm$core$Maybe$Just(v)
			});
	};
};
var $terezka$elm_charts$Chart$Attributes$height = function (v) {
	return function (config) {
		return _Utils_update(
			config,
			{cq: v});
	};
};
var $terezka$elm_charts$Chart$Attributes$margin = function (v) {
	return function (config) {
		return _Utils_update(
			config,
			{X: v});
	};
};
var $terezka$elm_charts$Chart$Attributes$moveDown = function (v) {
	return function (config) {
		return _Utils_update(
			config,
			{q: config.q + v});
	};
};
var $terezka$elm_charts$Internal$Property$Stacked = function (a) {
	return {$: 1, a: a};
};
var $terezka$elm_charts$Internal$Property$variation = F2(
	function (newVariation, property) {
		var update = function (config) {
			return _Utils_update(
				config,
				{
					c_: F2(
						function (ids, datum) {
							return _Utils_ap(
								A2(config.c_, ids, datum),
								A2(newVariation, ids, datum));
						})
				});
		};
		if (!property.$) {
			var config = property.a;
			return $terezka$elm_charts$Internal$Property$NotStacked(
				update(config));
		} else {
			var configs = property.a;
			return $terezka$elm_charts$Internal$Property$Stacked(
				A2($elm$core$List$map, update, configs));
		}
	});
var $terezka$elm_charts$Chart$variation = function (func) {
	return $terezka$elm_charts$Internal$Property$variation(
		F2(
			function (ids, datum) {
				return A2(func, ids.cd, datum);
			}));
};
var $author$project$Main$viewCategoryChart = function (entries) {
	var rows = A2(
		$elm$core$List$map,
		function (cat) {
			return {
				cc: $author$project$Main$categoryColor(cat),
				cx: $author$project$Main$categoryLabel(cat),
				bw: $elm$core$List$sum(
					A2(
						$elm$core$List$map,
						function ($) {
							return $.d;
						},
						A2(
							$elm$core$List$filter,
							function (e) {
								return _Utils_eq(e.h, cat);
							},
							entries)))
			};
		},
		$author$project$Main$allCategories);
	return A2(
		$terezka$elm_charts$Chart$chart,
		_List_fromArray(
			[
				$terezka$elm_charts$Chart$Attributes$height(140),
				$terezka$elm_charts$Chart$Attributes$margin(
				{bx: 28, bJ: 0, bT: 0, b3: 10})
			]),
		_List_fromArray(
			[
				A3(
				$terezka$elm_charts$Chart$bars,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$terezka$elm_charts$Chart$variation,
						F2(
							function (_v0, d) {
								return _List_fromArray(
									[
										$terezka$elm_charts$Chart$Attributes$color(d.cc)
									]);
							}),
						A2(
							$terezka$elm_charts$Chart$bar,
							function ($) {
								return $.bw;
							},
							_List_Nil))
					]),
				rows),
				A2(
				$terezka$elm_charts$Chart$binLabels,
				function ($) {
					return $.cx;
				},
				_List_fromArray(
					[
						$terezka$elm_charts$Chart$Attributes$moveDown(16),
						$terezka$elm_charts$Chart$Attributes$color('#7a8a80'),
						$terezka$elm_charts$Chart$Attributes$fontSize(9)
					]))
			]));
};
var $terezka$elm_charts$Internal$Svg$Linear = 0;
var $terezka$elm_charts$Chart$Attributes$linear = function (config) {
	return _Utils_update(
		config,
		{
			a7: $elm$core$Maybe$Just(0)
		});
};
var $terezka$elm_charts$Chart$interpolated = F2(
	function (y, inter) {
		return A2(
			$terezka$elm_charts$Internal$Property$notStacked,
			A2($elm$core$Basics$composeR, y, $elm$core$Maybe$Just),
			_Utils_ap(
				_List_fromArray(
					[$terezka$elm_charts$Chart$Attributes$linear]),
				inter));
	});
var $terezka$elm_charts$Chart$SeriesElement = F4(
	function (a, b, c, d) {
		return {$: 1, a: a, b: b, c: c, d: d};
	});
var $terezka$elm_charts$Internal$Legend$LineLegend = F3(
	function (a, b, c) {
		return {$: 1, a: a, b: b, c: c};
	});
var $terezka$elm_charts$Internal$Svg$defaultInterpolation = {g: _List_Nil, cc: $terezka$elm_charts$Internal$Helpers$pink, bl: _List_Nil, bz: $elm$core$Maybe$Nothing, a7: $elm$core$Maybe$Nothing, am: 0, c2: 1};
var $terezka$elm_charts$Internal$Helpers$noChange = $elm$core$Basics$identity;
var $terezka$elm_charts$Chart$Attributes$opacity = function (v) {
	return function (config) {
		return _Utils_update(
			config,
			{am: v});
	};
};
var $terezka$elm_charts$Internal$Legend$toDotLegends = F2(
	function (elIndex, properties) {
		var toInterConfig = function (attrs) {
			return A2($terezka$elm_charts$Internal$Helpers$apply, attrs, $terezka$elm_charts$Internal$Svg$defaultInterpolation);
		};
		var toDotLegend = F3(
			function (props, prop, colorIndex) {
				var defaultOpacity = ($elm$core$List$length(props) > 1) ? 0.4 : 0;
				var interAttr = _Utils_ap(
					_List_fromArray(
						[
							$terezka$elm_charts$Chart$Attributes$color(
							$terezka$elm_charts$Internal$Helpers$toDefaultColor(colorIndex)),
							$terezka$elm_charts$Chart$Attributes$opacity(defaultOpacity)
						]),
					prop.dz);
				var interConfig = toInterConfig(interAttr);
				var defaultName = 'Property #' + $elm$core$String$fromInt(colorIndex + 1);
				var defaultAttrs = _List_fromArray(
					[
						$terezka$elm_charts$Chart$Attributes$color(interConfig.cc),
						$terezka$elm_charts$Chart$Attributes$border(interConfig.cc),
						_Utils_eq(interConfig.a7, $elm$core$Maybe$Nothing) ? $terezka$elm_charts$Chart$Attributes$circle : $terezka$elm_charts$Internal$Helpers$noChange
					]);
				var dotAttrs = _Utils_ap(defaultAttrs, prop.dN);
				return A3(
					$terezka$elm_charts$Internal$Legend$LineLegend,
					A2($elm$core$Maybe$withDefault, defaultName, prop.cY),
					interAttr,
					dotAttrs);
			});
		return A2(
			$elm$core$List$indexedMap,
			F2(
				function (propIndex, f) {
					return f(elIndex + propIndex);
				}),
			A2(
				$elm$core$List$concatMap,
				function (ps) {
					return A2(
						$elm$core$List$map,
						toDotLegend(ps),
						ps);
				},
				A2($elm$core$List$map, $terezka$elm_charts$Internal$Property$toConfigs, properties)));
	});
var $terezka$elm_charts$Internal$Item$Dot = function (a) {
	return {$: 0, a: a};
};
var $terezka$elm_charts$Internal$Coordinates$Point = F2(
	function (x, y) {
		return {c3: x, c4: y};
	});
var $elm$svg$Svg$Attributes$fillRule = _VirtualDom_attribute('fill-rule');
var $terezka$elm_charts$Internal$Interpolation$linear = $elm$core$List$map(
	$elm$core$List$map(
		function (_v0) {
			var x = _v0.c3;
			var y = _v0.c4;
			return A2($terezka$elm_charts$Internal$Commands$Line, x, y);
		}));
var $terezka$elm_charts$Internal$Interpolation$First = {$: 0};
var $terezka$elm_charts$Internal$Interpolation$Previous = function (a) {
	return {$: 1, a: a};
};
var $terezka$elm_charts$Internal$Interpolation$monotoneCurve = F4(
	function (point0, point1, tangent0, tangent1) {
		var dx = (point1.c3 - point0.c3) / 3;
		return A6($terezka$elm_charts$Internal$Commands$CubicBeziers, point0.c3 + dx, point0.c4 + (dx * tangent0), point1.c3 - dx, point1.c4 - (dx * tangent1), point1.c3, point1.c4);
	});
var $terezka$elm_charts$Internal$Interpolation$slope2 = F3(
	function (point0, point1, t) {
		var h = point1.c3 - point0.c3;
		return (!(!h)) ? ((((3 * (point1.c4 - point0.c4)) / h) - t) / 2) : t;
	});
var $elm$core$Basics$isNaN = _Basics_isNaN;
var $terezka$elm_charts$Internal$Interpolation$sign = function (x) {
	return (x < 0) ? (-1) : 1;
};
var $terezka$elm_charts$Internal$Interpolation$toH = F2(
	function (h0, h1) {
		return (!h0) ? ((h1 < 0) ? (0 * (-1)) : h1) : h0;
	});
var $terezka$elm_charts$Internal$Interpolation$slope3 = F3(
	function (point0, point1, point2) {
		var h1 = point2.c3 - point1.c3;
		var h0 = point1.c3 - point0.c3;
		var s0h = A2($terezka$elm_charts$Internal$Interpolation$toH, h0, h1);
		var s0 = (point1.c4 - point0.c4) / s0h;
		var s1h = A2($terezka$elm_charts$Internal$Interpolation$toH, h1, h0);
		var s1 = (point2.c4 - point1.c4) / s1h;
		var p = ((s0 * h1) + (s1 * h0)) / (h0 + h1);
		var slope = ($terezka$elm_charts$Internal$Interpolation$sign(s0) + $terezka$elm_charts$Internal$Interpolation$sign(s1)) * A2(
			$elm$core$Basics$min,
			A2(
				$elm$core$Basics$min,
				$elm$core$Basics$abs(s0),
				$elm$core$Basics$abs(s1)),
			0.5 * $elm$core$Basics$abs(p));
		return $elm$core$Basics$isNaN(slope) ? 0 : slope;
	});
var $terezka$elm_charts$Internal$Interpolation$monotonePart = F2(
	function (points, _v0) {
		var tangent = _v0.a;
		var commands = _v0.b;
		var _v1 = _Utils_Tuple2(tangent, points);
		_v1$4:
		while (true) {
			if (!_v1.a.$) {
				if (_v1.b.b && _v1.b.b.b) {
					if (_v1.b.b.b.b) {
						var _v2 = _v1.a;
						var _v3 = _v1.b;
						var p0 = _v3.a;
						var _v4 = _v3.b;
						var p1 = _v4.a;
						var _v5 = _v4.b;
						var p2 = _v5.a;
						var rest = _v5.b;
						var t1 = A3($terezka$elm_charts$Internal$Interpolation$slope3, p0, p1, p2);
						var t0 = A3($terezka$elm_charts$Internal$Interpolation$slope2, p0, p1, t1);
						return A2(
							$terezka$elm_charts$Internal$Interpolation$monotonePart,
							A2(
								$elm$core$List$cons,
								p1,
								A2($elm$core$List$cons, p2, rest)),
							_Utils_Tuple2(
								$terezka$elm_charts$Internal$Interpolation$Previous(t1),
								_Utils_ap(
									commands,
									_List_fromArray(
										[
											A4($terezka$elm_charts$Internal$Interpolation$monotoneCurve, p0, p1, t0, t1)
										]))));
					} else {
						var _v9 = _v1.a;
						var _v10 = _v1.b;
						var p0 = _v10.a;
						var _v11 = _v10.b;
						var p1 = _v11.a;
						var t1 = A3($terezka$elm_charts$Internal$Interpolation$slope3, p0, p1, p1);
						return _Utils_Tuple2(
							$terezka$elm_charts$Internal$Interpolation$Previous(t1),
							_Utils_ap(
								commands,
								_List_fromArray(
									[
										A4($terezka$elm_charts$Internal$Interpolation$monotoneCurve, p0, p1, t1, t1),
										A2($terezka$elm_charts$Internal$Commands$Line, p1.c3, p1.c4)
									])));
					}
				} else {
					break _v1$4;
				}
			} else {
				if (_v1.b.b && _v1.b.b.b) {
					if (_v1.b.b.b.b) {
						var t0 = _v1.a.a;
						var _v6 = _v1.b;
						var p0 = _v6.a;
						var _v7 = _v6.b;
						var p1 = _v7.a;
						var _v8 = _v7.b;
						var p2 = _v8.a;
						var rest = _v8.b;
						var t1 = A3($terezka$elm_charts$Internal$Interpolation$slope3, p0, p1, p2);
						return A2(
							$terezka$elm_charts$Internal$Interpolation$monotonePart,
							A2(
								$elm$core$List$cons,
								p1,
								A2($elm$core$List$cons, p2, rest)),
							_Utils_Tuple2(
								$terezka$elm_charts$Internal$Interpolation$Previous(t1),
								_Utils_ap(
									commands,
									_List_fromArray(
										[
											A4($terezka$elm_charts$Internal$Interpolation$monotoneCurve, p0, p1, t0, t1)
										]))));
					} else {
						var t0 = _v1.a.a;
						var _v12 = _v1.b;
						var p0 = _v12.a;
						var _v13 = _v12.b;
						var p1 = _v13.a;
						var t1 = A3($terezka$elm_charts$Internal$Interpolation$slope3, p0, p1, p1);
						return _Utils_Tuple2(
							$terezka$elm_charts$Internal$Interpolation$Previous(t1),
							_Utils_ap(
								commands,
								_List_fromArray(
									[
										A4($terezka$elm_charts$Internal$Interpolation$monotoneCurve, p0, p1, t0, t1),
										A2($terezka$elm_charts$Internal$Commands$Line, p1.c3, p1.c4)
									])));
					}
				} else {
					break _v1$4;
				}
			}
		}
		return _Utils_Tuple2(tangent, commands);
	});
var $terezka$elm_charts$Internal$Interpolation$monotoneSection = F2(
	function (points, _v0) {
		var tangent = _v0.a;
		var acc = _v0.b;
		var _v1 = function () {
			if (points.b) {
				var p0 = points.a;
				var rest = points.b;
				return A2(
					$terezka$elm_charts$Internal$Interpolation$monotonePart,
					A2($elm$core$List$cons, p0, rest),
					_Utils_Tuple2(
						tangent,
						_List_fromArray(
							[
								A2($terezka$elm_charts$Internal$Commands$Line, p0.c3, p0.c4)
							])));
			} else {
				return _Utils_Tuple2(tangent, _List_Nil);
			}
		}();
		var t0 = _v1.a;
		var commands = _v1.b;
		return _Utils_Tuple2(
			t0,
			A2($elm$core$List$cons, commands, acc));
	});
var $terezka$elm_charts$Internal$Interpolation$monotone = function (sections) {
	return A3(
		$elm$core$List$foldr,
		$terezka$elm_charts$Internal$Interpolation$monotoneSection,
		_Utils_Tuple2($terezka$elm_charts$Internal$Interpolation$First, _List_Nil),
		sections).b;
};
var $terezka$elm_charts$Internal$Interpolation$Point = F2(
	function (x, y) {
		return {c3: x, c4: y};
	});
var $terezka$elm_charts$Internal$Interpolation$after = F2(
	function (a, b) {
		return _List_fromArray(
			[
				a,
				A2($terezka$elm_charts$Internal$Interpolation$Point, b.c3, a.c4),
				b
			]);
	});
var $terezka$elm_charts$Internal$Interpolation$stepped = function (sections) {
	var expand = F2(
		function (result, section) {
			expand:
			while (true) {
				if (section.b) {
					if (section.b.b) {
						var a = section.a;
						var _v1 = section.b;
						var b = _v1.a;
						var rest = _v1.b;
						var $temp$result = _Utils_ap(
							result,
							A2($terezka$elm_charts$Internal$Interpolation$after, a, b)),
							$temp$section = A2($elm$core$List$cons, b, rest);
						result = $temp$result;
						section = $temp$section;
						continue expand;
					} else {
						var last = section.a;
						return result;
					}
				} else {
					return result;
				}
			}
		});
	return A2(
		$elm$core$List$map,
		A2(
			$elm$core$Basics$composeR,
			expand(_List_Nil),
			$elm$core$List$map(
				function (_v2) {
					var x = _v2.c3;
					var y = _v2.c4;
					return A2($terezka$elm_charts$Internal$Commands$Line, x, y);
				})),
		sections);
};
var $terezka$elm_charts$Internal$Svg$last = function (list) {
	return $elm$core$List$head(
		A2(
			$elm$core$List$drop,
			$elm$core$List$length(list) - 1,
			list));
};
var $terezka$elm_charts$Internal$Svg$withBorder = F2(
	function (stuff, func) {
		if (stuff.b) {
			var first = stuff.a;
			var rest = stuff.b;
			return $elm$core$Maybe$Just(
				A2(
					func,
					first,
					A2(
						$elm$core$Maybe$withDefault,
						first,
						$terezka$elm_charts$Internal$Svg$last(rest))));
		} else {
			return $elm$core$Maybe$Nothing;
		}
	});
var $terezka$elm_charts$Internal$Svg$toCommands = F4(
	function (method, toX, toY, data) {
		var toSets = F2(
			function (ps, cmds) {
				return A2(
					$terezka$elm_charts$Internal$Svg$withBorder,
					ps,
					F2(
						function (first, last_) {
							return _Utils_Tuple3(first, cmds, last_);
						}));
			});
		var fold = F2(
			function (datum_, acc) {
				var _v1 = toY(datum_);
				if (!_v1.$) {
					var y_ = _v1.a;
					if (acc.b) {
						var latest = acc.a;
						var rest = acc.b;
						return A2(
							$elm$core$List$cons,
							_Utils_ap(
								latest,
								_List_fromArray(
									[
										{
										c3: toX(datum_),
										c4: y_
									}
									])),
							rest);
					} else {
						return A2(
							$elm$core$List$cons,
							_List_fromArray(
								[
									{
									c3: toX(datum_),
									c4: y_
								}
								]),
							acc);
					}
				} else {
					return A2($elm$core$List$cons, _List_Nil, acc);
				}
			});
		var points = $elm$core$List$reverse(
			A3($elm$core$List$foldl, fold, _List_Nil, data));
		var commands = function () {
			switch (method) {
				case 0:
					return $terezka$elm_charts$Internal$Interpolation$linear(points);
				case 1:
					return $terezka$elm_charts$Internal$Interpolation$monotone(points);
				default:
					return $terezka$elm_charts$Internal$Interpolation$stepped(points);
			}
		}();
		return A2(
			$elm$core$List$filterMap,
			$elm$core$Basics$identity,
			A3($elm$core$List$map2, toSets, points, commands));
	});
var $terezka$elm_charts$Internal$Svg$area = F6(
	function (plane, toX, toY2M, toY, config, data) {
		var _v0 = function () {
			var _v1 = config.bz;
			if (_v1.$ === 1) {
				return _Utils_Tuple2(
					$elm$svg$Svg$text(''),
					config.cc);
			} else {
				var design = _v1.a;
				return A2($terezka$elm_charts$Internal$Svg$toPattern, config.cc, design);
			}
		}();
		var patternDefs = _v0.a;
		var fill = _v0.b;
		var view = function (cmds) {
			return A4(
				$terezka$elm_charts$Internal$Svg$withAttrs,
				config.g,
				$elm$svg$Svg$path,
				_List_fromArray(
					[
						$elm$svg$Svg$Attributes$class('elm-charts__area-section'),
						$elm$svg$Svg$Attributes$fill(fill),
						$elm$svg$Svg$Attributes$fillOpacity(
						$elm$core$String$fromFloat(config.am)),
						$elm$svg$Svg$Attributes$strokeWidth('0'),
						$elm$svg$Svg$Attributes$fillRule('evenodd'),
						$elm$svg$Svg$Attributes$d(
						A2($terezka$elm_charts$Internal$Commands$description, plane, cmds)),
						$terezka$elm_charts$Internal$Svg$withinChartArea(plane)
					]),
				_List_Nil);
		};
		var withUnder = F2(
			function (_v5, _v6) {
				var firstBottom = _v5.a;
				var cmdsBottom = _v5.b;
				var endBottom = _v5.c;
				var firstTop = _v6.a;
				var cmdsTop = _v6.b;
				var endTop = _v6.c;
				return view(
					_Utils_ap(
						_List_fromArray(
							[
								A2($terezka$elm_charts$Internal$Commands$Move, firstBottom.c3, firstBottom.c4),
								A2($terezka$elm_charts$Internal$Commands$Line, firstTop.c3, firstTop.c4)
							]),
						_Utils_ap(
							cmdsTop,
							_Utils_ap(
								_List_fromArray(
									[
										A2($terezka$elm_charts$Internal$Commands$Move, firstBottom.c3, firstBottom.c4)
									]),
								_Utils_ap(
									cmdsBottom,
									_List_fromArray(
										[
											A2($terezka$elm_charts$Internal$Commands$Line, endTop.c3, endTop.c4)
										]))))));
			});
		var withoutUnder = function (_v4) {
			var first = _v4.a;
			var cmds = _v4.b;
			var end = _v4.c;
			return view(
				_Utils_ap(
					_List_fromArray(
						[
							A2($terezka$elm_charts$Internal$Commands$Move, first.c3, 0),
							A2($terezka$elm_charts$Internal$Commands$Line, first.c3, first.c4)
						]),
					_Utils_ap(
						cmds,
						_List_fromArray(
							[
								A2($terezka$elm_charts$Internal$Commands$Line, end.c3, 0)
							]))));
		};
		if (config.am <= 0) {
			return $elm$svg$Svg$text('');
		} else {
			var _v2 = config.a7;
			if (_v2.$ === 1) {
				return $elm$svg$Svg$text('');
			} else {
				var method = _v2.a;
				return A2(
					$elm$svg$Svg$g,
					_List_fromArray(
						[
							$elm$svg$Svg$Attributes$class('elm-charts__area-sections')
						]),
					function () {
						if (toY2M.$ === 1) {
							return A2(
								$elm$core$List$cons,
								patternDefs,
								A2(
									$elm$core$List$map,
									withoutUnder,
									A4($terezka$elm_charts$Internal$Svg$toCommands, method, toX, toY, data)));
						} else {
							var toY2 = toY2M.a;
							return A2(
								$elm$core$List$cons,
								patternDefs,
								A3(
									$elm$core$List$map2,
									withUnder,
									A4($terezka$elm_charts$Internal$Svg$toCommands, method, toX, toY2, data),
									A4($terezka$elm_charts$Internal$Svg$toCommands, method, toX, toY, data)));
						}
					}());
			}
		}
	});
var $terezka$elm_charts$Internal$Svg$interpolation = F5(
	function (plane, toX, toY, config, data) {
		var view = function (_v1) {
			var first = _v1.a;
			var cmds = _v1.b;
			return A4(
				$terezka$elm_charts$Internal$Svg$withAttrs,
				config.g,
				$elm$svg$Svg$path,
				_List_fromArray(
					[
						$elm$svg$Svg$Attributes$class('elm-charts__interpolation-section'),
						$elm$svg$Svg$Attributes$fill('transparent'),
						$elm$svg$Svg$Attributes$stroke(config.cc),
						$elm$svg$Svg$Attributes$strokeDasharray(
						A2(
							$elm$core$String$join,
							' ',
							A2($elm$core$List$map, $elm$core$String$fromFloat, config.bl))),
						$elm$svg$Svg$Attributes$strokeWidth(
						$elm$core$String$fromFloat(config.c2)),
						$elm$svg$Svg$Attributes$d(
						A2(
							$terezka$elm_charts$Internal$Commands$description,
							plane,
							A2(
								$elm$core$List$cons,
								A2($terezka$elm_charts$Internal$Commands$Move, first.c3, first.c4),
								cmds))),
						$terezka$elm_charts$Internal$Svg$withinChartArea(plane)
					]),
				_List_Nil);
		};
		var _v0 = config.a7;
		if (_v0.$ === 1) {
			return $elm$svg$Svg$text('');
		} else {
			var method = _v0.a;
			return A2(
				$elm$svg$Svg$g,
				_List_fromArray(
					[
						$elm$svg$Svg$Attributes$class('elm-charts__interpolation-sections')
					]),
				A2(
					$elm$core$List$map,
					view,
					A4($terezka$elm_charts$Internal$Svg$toCommands, method, toX, toY, data)));
		}
	});
var $elm$core$Maybe$map2 = F3(
	function (func, ma, mb) {
		if (ma.$ === 1) {
			return $elm$core$Maybe$Nothing;
		} else {
			var a = ma.a;
			if (mb.$ === 1) {
				return $elm$core$Maybe$Nothing;
			} else {
				var b = mb.a;
				return $elm$core$Maybe$Just(
					A2(func, a, b));
			}
		}
	});
var $terezka$elm_charts$Internal$Svg$toRadius = F2(
	function (size_, shape) {
		var area_ = (2 * $elm$core$Basics$pi) * size_;
		switch (shape) {
			case 0:
				return $elm$core$Basics$sqrt(area_ / $elm$core$Basics$pi);
			case 1:
				var side = $elm$core$Basics$sqrt(
					(area_ * 4) / $elm$core$Basics$sqrt(3));
				return $elm$core$Basics$sqrt(3) * side;
			case 2:
				return $elm$core$Basics$sqrt(area_) / 2;
			case 3:
				return $elm$core$Basics$sqrt(area_) / 2;
			case 4:
				return $elm$core$Basics$sqrt(area_ / 4);
			default:
				return $elm$core$Basics$sqrt(area_ / 4);
		}
	});
var $terezka$elm_charts$Internal$Produce$toDotSeries = F4(
	function (elementIndex, toX, properties, data) {
		var forEachDataPoint = F9(
			function (absoluteIndex, stackSeriesConfigIndex, lineSeriesConfigIndex, lineSeriesConfig, interpolationConfig, defaultColor, defaultOpacity, dataIndex, datum) {
				var y = A2(
					$elm$core$Maybe$withDefault,
					0,
					lineSeriesConfig.bd(datum));
				var x = toX(datum);
				var limits = {aX: x, bi: x, ee: y, b5: y};
				var identification = {c7: absoluteIndex, cd: dataIndex, $7: elementIndex, dT: lineSeriesConfigIndex, dV: stackSeriesConfigIndex};
				var defaultAttrs = _List_fromArray(
					[
						$terezka$elm_charts$Chart$Attributes$color(interpolationConfig.cc),
						$terezka$elm_charts$Chart$Attributes$border(interpolationConfig.cc),
						_Utils_eq(interpolationConfig.a7, $elm$core$Maybe$Nothing) ? $terezka$elm_charts$Chart$Attributes$circle : $terezka$elm_charts$Internal$Helpers$noChange
					]);
				var dotAttrs = _Utils_ap(
					defaultAttrs,
					_Utils_ap(
						lineSeriesConfig.dN,
						A2(lineSeriesConfig.c_, identification, datum)));
				var dotConfig = A2($terezka$elm_charts$Internal$Helpers$apply, dotAttrs, $terezka$elm_charts$Internal$Svg$defaultDot);
				var radius = A2(
					$elm$core$Maybe$withDefault,
					0,
					A2(
						$elm$core$Maybe$map,
						$terezka$elm_charts$Internal$Svg$toRadius(dotConfig.cU),
						dotConfig.aR));
				var tooltipTextColor = (dotConfig.cc === 'white') ? ((dotConfig.N === 'white') ? interpolationConfig.cc : dotConfig.N) : dotConfig.cc;
				return _Utils_Tuple2(
					limits,
					F2(
						function (topLevel, localPlane) {
							var radiusY = A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianY, localPlane, radius);
							var radiusX = A2($terezka$elm_charts$Internal$Coordinates$scaleCartesianX, localPlane, radius);
							var position = {aX: x - radiusX, bi: x + radiusX, ee: y - radiusY, b5: y + radiusY};
							return A2(
								$terezka$elm_charts$Internal$Item$Rendered,
								{
									cc: tooltipTextColor,
									dj: datum,
									dw: identification,
									dB: !_Utils_eq(
										lineSeriesConfig.bv(datum),
										$elm$core$Maybe$Nothing),
									dH: lineSeriesConfig.cY,
									dN: $terezka$elm_charts$Internal$Item$Dot(dotConfig),
									d1: $elm$core$Basics$identity,
									d7: lineSeriesConfig.d7(datum),
									aX: x,
									bi: x,
									c4: y
								},
								{
									I: limits,
									dC: A3($terezka$elm_charts$Internal$Coordinates$convertPos, topLevel, localPlane, limits),
									dD: localPlane,
									dL: topLevel,
									F: position,
									dM: A3($terezka$elm_charts$Internal$Coordinates$convertPos, topLevel, localPlane, position),
									cL: function (_v11) {
										var _v12 = lineSeriesConfig.bv(datum);
										if (_v12.$ === 1) {
											return $elm$svg$Svg$text('');
										} else {
											return A5(
												$terezka$elm_charts$Internal$Svg$dot,
												localPlane,
												function ($) {
													return $.c3;
												},
												function ($) {
													return $.c4;
												},
												dotConfig,
												A2($terezka$elm_charts$Internal$Coordinates$Point, x, y));
										}
									},
									d6: function (_v13) {
										return _List_fromArray(
											[
												A3(
												$terezka$elm_charts$Internal$Produce$tooltipRow,
												tooltipTextColor,
												A2($terezka$elm_charts$Internal$Produce$toDefaultName, identification, lineSeriesConfig.cY),
												lineSeriesConfig.d7(datum))
											]);
									}
								});
						}));
			});
		var forEachLine = F5(
			function (isStacked, absoluteIndex, stackSeriesConfigIndex, lineSeriesConfigIndex, lineSeriesConfig) {
				var defaultOpacity = isStacked ? 0.4 : 0;
				var absoluteIndexNew = absoluteIndex + lineSeriesConfigIndex;
				var defaultColor = $terezka$elm_charts$Internal$Helpers$toDefaultColor(absoluteIndexNew);
				var interpolationAttrs = _List_fromArray(
					[
						$terezka$elm_charts$Chart$Attributes$color(defaultColor),
						$terezka$elm_charts$Chart$Attributes$opacity(defaultOpacity)
					]);
				var interpolationConfig = A2(
					$terezka$elm_charts$Internal$Helpers$apply,
					_Utils_ap(interpolationAttrs, lineSeriesConfig.dz),
					$terezka$elm_charts$Internal$Svg$defaultInterpolation);
				var viewSeries = F2(
					function (plane, dotItems) {
						var toBottom = function (datum) {
							return A3(
								$elm$core$Maybe$map2,
								F2(
									function (y, ySum) {
										return ySum - y;
									}),
								lineSeriesConfig.bv(datum),
								lineSeriesConfig.bd(datum));
						};
						return A2(
							$elm$svg$Svg$g,
							_List_fromArray(
								[
									$elm$svg$Svg$Attributes$class('elm-charts__series')
								]),
							_List_fromArray(
								[
									A6(
									$terezka$elm_charts$Internal$Svg$area,
									plane,
									toX,
									$elm$core$Maybe$Just(toBottom),
									lineSeriesConfig.bd,
									interpolationConfig,
									data),
									A5($terezka$elm_charts$Internal$Svg$interpolation, plane, toX, lineSeriesConfig.bd, interpolationConfig, data),
									A2(
									$elm$svg$Svg$g,
									_List_fromArray(
										[
											$elm$svg$Svg$Attributes$class('elm-charts__dots')
										]),
									A2($elm$core$List$map, $terezka$elm_charts$Internal$Item$render, dotItems))
								]));
					});
				var _v8 = $elm$core$List$unzip(
					A2(
						$elm$core$List$indexedMap,
						A7(forEachDataPoint, absoluteIndexNew, stackSeriesConfigIndex, lineSeriesConfigIndex, lineSeriesConfig, interpolationConfig, defaultColor, defaultOpacity),
						data));
				var limits = _v8.a;
				var toDotItems = _v8.b;
				return _Utils_Tuple2(
					limits,
					F2(
						function (topLevel, localPlane) {
							var dotItems = A2(
								$elm$core$List$map,
								function (i) {
									return A2(i, topLevel, localPlane);
								},
								toDotItems);
							return A2(
								$terezka$elm_charts$Internal$Helpers$withFirst,
								dotItems,
								F2(
									function (first, rest) {
										var groupPosition = A2($terezka$elm_charts$Internal$Coordinates$foldPosition, $terezka$elm_charts$Internal$Item$getPosition, dotItems);
										var groupLimits = A2($terezka$elm_charts$Internal$Coordinates$foldPosition, $terezka$elm_charts$Internal$Item$getLimits, dotItems);
										return A2(
											$terezka$elm_charts$Internal$Item$Rendered,
											_Utils_Tuple2(first, rest),
											{
												I: groupLimits,
												dC: A3($terezka$elm_charts$Internal$Coordinates$convertPos, topLevel, localPlane, groupLimits),
												dD: localPlane,
												dL: topLevel,
												F: groupPosition,
												dM: A3($terezka$elm_charts$Internal$Coordinates$convertPos, topLevel, localPlane, groupPosition),
												cL: function (_v9) {
													return A2(viewSeries, localPlane, dotItems);
												},
												d6: function (_v10) {
													return _List_fromArray(
														[
															A2(
															$elm$html$Html$table,
															_List_fromArray(
																[
																	A2($elm$html$Html$Attributes$style, 'margin', '0')
																]),
															A2($elm$core$List$concatMap, $terezka$elm_charts$Internal$Item$tooltip, dotItems))
														]);
												}
											});
									}));
						}));
			});
		var forEachStackSeriesConfig = F2(
			function (stackSeriesConfig, _v6) {
				var absoluteIndex = _v6.a;
				var stackSeriesConfigIndex = _v6.b;
				var _v7 = _v6.c;
				var limits = _v7.a;
				var items = _v7.b;
				var _v4 = $elm$core$List$unzip(
					function () {
						if (!stackSeriesConfig.$) {
							var lineSeriesConfig = stackSeriesConfig.a;
							return _List_fromArray(
								[
									A5(forEachLine, false, absoluteIndex, stackSeriesConfigIndex, 0, lineSeriesConfig)
								]);
						} else {
							var lineSeriesConfigs = stackSeriesConfig.a;
							return A2(
								$elm$core$List$indexedMap,
								A3(forEachLine, true, absoluteIndex, stackSeriesConfigIndex),
								lineSeriesConfigs);
						}
					}());
				var newLimits = _v4.a;
				var lineItems = _v4.b;
				return _Utils_Tuple3(
					absoluteIndex + $elm$core$List$length(lineItems),
					stackSeriesConfigIndex + 1,
					_Utils_Tuple2(
						_Utils_ap(
							limits,
							$elm$core$List$concat(newLimits)),
						F2(
							function (topLevel, localPlane) {
								return _Utils_ap(
									A2(items, topLevel, localPlane),
									A2(
										$elm$core$List$filterMap,
										$elm$core$Basics$identity,
										A2(
											$elm$core$List$map,
											function (i) {
												return A2(i, topLevel, localPlane);
											},
											lineItems)));
							})));
			});
		return function (_v2) {
			var newElementIndex = _v2.a;
			var _v3 = _v2.c;
			var limits = _v3.a;
			var items = _v3.b;
			return _Utils_Tuple3(newElementIndex, limits, items);
		}(
			A3(
				$elm$core$List$foldl,
				forEachStackSeriesConfig,
				_Utils_Tuple3(
					elementIndex,
					0,
					_Utils_Tuple2(
						_List_Nil,
						F2(
							function (_v0, _v1) {
								return _List_Nil;
							}))),
				properties));
	});
var $terezka$elm_charts$Chart$seriesMap = F4(
	function (mapData, toX, properties, data) {
		return $terezka$elm_charts$Chart$Indexed(
			F2(
				function (_v0, index) {
					var legends = A2($terezka$elm_charts$Internal$Legend$toDotLegends, index, properties);
					var _v1 = A4($terezka$elm_charts$Internal$Produce$toDotSeries, index, toX, properties, data);
					var newElementIndex = _v1.a;
					var limits = _v1.b;
					var items = _v1.c;
					var toItems = F2(
						function (topLevel, localPlane) {
							return A2(
								$elm$core$List$concatMap,
								A2(
									$elm$core$Basics$composeR,
									$terezka$elm_charts$Internal$Many$getMembers,
									$elm$core$List$map(
										$terezka$elm_charts$Internal$Item$map(mapData))),
								A2(items, topLevel, localPlane));
						});
					return _Utils_Tuple2(
						A4(
							$terezka$elm_charts$Chart$SeriesElement,
							A2($terezka$elm_charts$Internal$Coordinates$foldPosition, $elm$core$Basics$identity, limits),
							toItems,
							legends,
							F2(
								function (topLevel, p) {
									return A2(
										$elm$svg$Svg$map,
										$elm$core$Basics$never,
										A2(
											$elm$svg$Svg$g,
											_List_fromArray(
												[
													$elm$svg$Svg$Attributes$class('elm-charts__dot-series')
												]),
											A2(
												$elm$core$List$map,
												$terezka$elm_charts$Internal$Item$render,
												A2(items, topLevel, p))));
								})),
						newElementIndex);
				}));
	});
var $terezka$elm_charts$Chart$series = F3(
	function (toX, properties, data) {
		return A4($terezka$elm_charts$Chart$seriesMap, $elm$core$Basics$identity, toX, properties, data);
	});
var $author$project$Main$viewCumulativeChart = function (entries) {
	var sorted = $elm$core$List$reverse(
		$author$project$Main$uniqueDates(entries));
	var points = A2(
		$elm$core$List$indexedMap,
		F2(
			function (i, date) {
				return {
					c3: i + 1,
					c4: $elm$core$List$sum(
						A2(
							$elm$core$List$map,
							function ($) {
								return $.d;
							},
							A2(
								$elm$core$List$filter,
								function (e) {
									return _Utils_cmp(e.i, date) < 1;
								},
								entries)))
				};
			}),
		sorted);
	return A2(
		$terezka$elm_charts$Chart$chart,
		_List_fromArray(
			[
				$terezka$elm_charts$Chart$Attributes$height(160),
				$terezka$elm_charts$Chart$Attributes$margin(
				{bx: 10, bJ: 0, bT: 0, b3: 10})
			]),
		_List_fromArray(
			[
				A3(
				$terezka$elm_charts$Chart$series,
				function ($) {
					return $.c3;
				},
				_List_fromArray(
					[
						A3(
						$terezka$elm_charts$Chart$interpolated,
						function ($) {
							return $.c4;
						},
						_List_fromArray(
							[
								$terezka$elm_charts$Chart$Attributes$color('#4090e0'),
								$terezka$elm_charts$Chart$Attributes$width(2)
							]),
						_List_Nil)
					]),
				points)
			]));
};
var $author$project$Main$viewDailyChart = function (entries) {
	var days = A2(
		$elm$core$List$map,
		function (date) {
			return {
				i: A3($elm$core$String$slice, 5, 10, date),
				bw: $elm$core$List$sum(
					A2(
						$elm$core$List$map,
						function ($) {
							return $.d;
						},
						A2(
							$elm$core$List$filter,
							function (e) {
								return _Utils_eq(e.i, date);
							},
							entries)))
			};
		},
		$elm$core$List$reverse(
			$author$project$Main$uniqueDates(entries)));
	return A2(
		$terezka$elm_charts$Chart$chart,
		_List_fromArray(
			[
				$terezka$elm_charts$Chart$Attributes$height(140),
				$terezka$elm_charts$Chart$Attributes$margin(
				{bx: 28, bJ: 0, bT: 0, b3: 10})
			]),
		_List_fromArray(
			[
				A3(
				$terezka$elm_charts$Chart$bars,
				_List_Nil,
				_List_fromArray(
					[
						A2(
						$terezka$elm_charts$Chart$bar,
						function ($) {
							return $.bw;
						},
						_List_fromArray(
							[
								$terezka$elm_charts$Chart$Attributes$color('#e8a020')
							]))
					]),
				days),
				A2(
				$terezka$elm_charts$Chart$binLabels,
				function ($) {
					return $.i;
				},
				_List_fromArray(
					[
						$terezka$elm_charts$Chart$Attributes$moveDown(16),
						$terezka$elm_charts$Chart$Attributes$color('#7a8a80'),
						$terezka$elm_charts$Chart$Attributes$fontSize(8)
					]))
			]));
};
var $author$project$Main$viewStatsTab = function (model) {
	var entries = model.U;
	var median = $author$project$Main$medianAmount(entries);
	var numDays = $elm$core$List$length(
		$author$project$Main$uniqueDates(entries));
	var numEntries = $elm$core$List$length(entries);
	var top5 = A2(
		$elm$core$List$take,
		5,
		A2(
			$elm$core$List$sortBy,
			function (e) {
				return -e.d;
			},
			entries));
	var topCat = $author$project$Main$topCategory(entries);
	var total = $elm$core$List$sum(
		A2(
			$elm$core$List$map,
			function ($) {
				return $.d;
			},
			entries));
	var daysIn = ((model.c.ax !== '') && (model.K !== '')) ? (($author$project$Main$isoToDayCount(model.K) - $author$project$Main$isoToDayCount(model.c.ax)) + 1) : 0;
	var bigDay = $author$project$Main$biggestDay(entries);
	var avgPerEntry = (numEntries > 0) ? (total / numEntries) : 0;
	var avgPerDay = (numDays > 0) ? (total / numDays) : 0;
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'padding', '20px')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$h2,
				_List_fromArray(
					[$author$project$Main$sectionHead]),
				_List_fromArray(
					[
						$elm$html$Html$text('STATS')
					])),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'display', 'grid'),
						A2($elm$html$Html$Attributes$style, 'grid-template-columns', '1fr 1fr'),
						A2($elm$html$Html$Attributes$style, 'gap', '12px'),
						A2($elm$html$Html$Attributes$style, 'margin-bottom', '24px')
					]),
				_List_fromArray(
					[
						A2(
						$author$project$Main$statCard,
						'TOTAL SPENT',
						$author$project$Main$formatAmount(total)),
						A2(
						$author$project$Main$statCard,
						'ENTRIES',
						$elm$core$String$fromInt(numEntries)),
						A2(
						$author$project$Main$statCard,
						'DAYS ON ROAD',
						$elm$core$String$fromInt(numDays)),
						A2(
						$author$project$Main$statCard,
						'AVG / DAY',
						$author$project$Main$formatAmount(avgPerDay)),
						A2(
						$author$project$Main$statCard,
						'AVG / ENTRY',
						$author$project$Main$formatAmount(avgPerEntry)),
						A2(
						$author$project$Main$statCard,
						'MEDIAN',
						$author$project$Main$formatAmount(median)),
						A2(
						$author$project$Main$statCard,
						'TOP CATEGORY',
						A2(
							$elm$core$Maybe$withDefault,
							'—',
							A2(
								$elm$core$Maybe$map,
								function (c) {
									return $author$project$Main$categoryIcon(c) + (' ' + $author$project$Main$categoryLabel(c));
								},
								topCat))),
						(numDays > 1) ? A2(
						$author$project$Main$statCard,
						'BIGGEST DAY',
						A2(
							$elm$core$Maybe$withDefault,
							'—',
							A2(
								$elm$core$Maybe$map,
								function (_v0) {
									var d = _v0.a;
									var t = _v0.b;
									return A3($elm$core$String$slice, 5, 10, d) + ('  ' + $author$project$Main$formatAmount(t));
								},
								bigDay))) : A2(
						$author$project$Main$statCard,
						'ENTRIES TODAY',
						$elm$core$String$fromInt(numEntries)),
						A2(
						$author$project$Main$statCard,
						'DAYS INTO TRIP',
						(daysIn > 0) ? $elm$core$String$fromInt(daysIn) : '—'),
						A2(
						$author$project$Main$statCard,
						'PROJ / 30 DAYS',
						(avgPerDay > 0) ? $author$project$Main$formatAmount(avgPerDay * 30) : '—')
					])),
				$elm$core$List$isEmpty(entries) ? $elm$html$Html$text('') : A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'background', '#161918'),
						A2($elm$html$Html$Attributes$style, 'border-radius', '10px'),
						A2($elm$html$Html$Attributes$style, 'padding', '20px'),
						A2($elm$html$Html$Attributes$style, 'margin-bottom', '16px')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'font-size', '11px'),
								A2($elm$html$Html$Attributes$style, 'letter-spacing', '0.1em'),
								A2($elm$html$Html$Attributes$style, 'color', '#7a8a80'),
								A2($elm$html$Html$Attributes$style, 'margin-bottom', '8px')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('BY CATEGORY')
							])),
						$author$project$Main$viewCategoryChart(entries)
					])),
				(numDays > 1) ? A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'background', '#161918'),
						A2($elm$html$Html$Attributes$style, 'border-radius', '10px'),
						A2($elm$html$Html$Attributes$style, 'padding', '20px'),
						A2($elm$html$Html$Attributes$style, 'margin-bottom', '16px')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'font-size', '11px'),
								A2($elm$html$Html$Attributes$style, 'letter-spacing', '0.1em'),
								A2($elm$html$Html$Attributes$style, 'color', '#7a8a80'),
								A2($elm$html$Html$Attributes$style, 'margin-bottom', '8px')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('DAILY SPENDING')
							])),
						$author$project$Main$viewDailyChart(entries)
					])) : $elm$html$Html$text(''),
				(numDays > 1) ? A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'background', '#161918'),
						A2($elm$html$Html$Attributes$style, 'border-radius', '10px'),
						A2($elm$html$Html$Attributes$style, 'padding', '20px'),
						A2($elm$html$Html$Attributes$style, 'margin-bottom', '16px')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'font-size', '11px'),
								A2($elm$html$Html$Attributes$style, 'letter-spacing', '0.1em'),
								A2($elm$html$Html$Attributes$style, 'color', '#7a8a80'),
								A2($elm$html$Html$Attributes$style, 'margin-bottom', '8px')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('CUMULATIVE SPEND')
							])),
						$author$project$Main$viewCumulativeChart(entries)
					])) : $elm$html$Html$text(''),
				$elm$core$List$isEmpty(top5) ? $elm$html$Html$text('') : A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'background', '#161918'),
						A2($elm$html$Html$Attributes$style, 'border-radius', '10px'),
						A2($elm$html$Html$Attributes$style, 'padding', '20px')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								A2($elm$html$Html$Attributes$style, 'font-size', '11px'),
								A2($elm$html$Html$Attributes$style, 'letter-spacing', '0.1em'),
								A2($elm$html$Html$Attributes$style, 'color', '#7a8a80'),
								A2($elm$html$Html$Attributes$style, 'margin-bottom', '12px')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('TOP 5 LARGEST')
							])),
						A2(
						$elm$html$Html$div,
						_List_Nil,
						A2(
							$elm$core$List$indexedMap,
							F2(
								function (i, entry) {
									return A2(
										$elm$html$Html$div,
										_List_fromArray(
											[
												A2($elm$html$Html$Attributes$style, 'display', 'flex'),
												A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
												A2($elm$html$Html$Attributes$style, 'gap', '12px'),
												A2($elm$html$Html$Attributes$style, 'padding', '10px 0'),
												A2(
												$elm$html$Html$Attributes$style,
												'border-bottom',
												(_Utils_cmp(
													i,
													$elm$core$List$length(top5) - 1) < 0) ? '1px solid #2a3230' : 'none')
											]),
										_List_fromArray(
											[
												A2(
												$elm$html$Html$span,
												_List_fromArray(
													[
														A2($elm$html$Html$Attributes$style, 'color', '#4a5a50'),
														A2($elm$html$Html$Attributes$style, 'font-family', 'monospace'),
														A2($elm$html$Html$Attributes$style, 'width', '20px')
													]),
												_List_fromArray(
													[
														$elm$html$Html$text(
														$elm$core$String$fromInt(i + 1) + '.')
													])),
												A2(
												$elm$html$Html$span,
												_List_fromArray(
													[
														A2($elm$html$Html$Attributes$style, 'font-size', '18px')
													]),
												_List_fromArray(
													[
														$elm$html$Html$text(
														$author$project$Main$categoryIcon(entry.h))
													])),
												A2(
												$elm$html$Html$div,
												_List_fromArray(
													[
														A2($elm$html$Html$Attributes$style, 'flex', '1')
													]),
												_List_fromArray(
													[
														A2(
														$elm$html$Html$div,
														_List_fromArray(
															[
																A2($elm$html$Html$Attributes$style, 'font-size', '14px')
															]),
														_List_fromArray(
															[
																$elm$html$Html$text(
																(entry.m !== '') ? entry.m : $author$project$Main$categoryLabel(entry.h))
															])),
														A2(
														$elm$html$Html$div,
														_List_fromArray(
															[
																A2($elm$html$Html$Attributes$style, 'font-size', '11px'),
																A2($elm$html$Html$Attributes$style, 'color', '#7a8a80')
															]),
														_List_fromArray(
															[
																$elm$html$Html$text(entry.i)
															]))
													])),
												A2(
												$elm$html$Html$span,
												_List_fromArray(
													[
														A2($elm$html$Html$Attributes$style, 'font-family', 'monospace'),
														A2($elm$html$Html$Attributes$style, 'color', '#e8a020'),
														A2($elm$html$Html$Attributes$style, 'font-size', '16px')
													]),
												_List_fromArray(
													[
														$elm$html$Html$text(
														$author$project$Main$formatAmount(entry.d))
													]))
											]));
								}),
							top5))
					]))
			]));
};
var $author$project$Main$viewToast = function (toast) {
	if (toast.$ === 1) {
		return $elm$html$Html$text('');
	} else {
		var message = toast.a;
		return A2(
			$elm$html$Html$div,
			_List_fromArray(
				[
					$elm$html$Html$Attributes$class('fixed bottom-16 left-4 right-4 z-50 flex items-center gap-3 rounded-xl px-4 py-3 bg-[#1e2220] border border-[#e85030] shadow-lg')
				]),
			_List_fromArray(
				[
					A2(
					$elm$html$Html$span,
					_List_fromArray(
						[
							$elm$html$Html$Attributes$class('text-[#e8c080] text-sm flex-1')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text(message)
						])),
					A2(
					$elm$html$Html$button,
					_List_fromArray(
						[
							$elm$html$Html$Events$onClick($author$project$Main$ToastExpired),
							$elm$html$Html$Attributes$class('bg-transparent border-none text-[#7a8a80] text-lg leading-none cursor-pointer p-0 flex-shrink-0')
						]),
					_List_fromArray(
						[
							$elm$html$Html$text('✕')
						]))
				]));
	}
};
var $author$project$Main$viewAuth = function (as_) {
	return A2(
		$elm$html$Html$div,
		_List_Nil,
		_List_fromArray(
			[
				$author$project$Main$viewHeader(as_),
				$author$project$Main$viewErrorBanner(as_.ai),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'padding-bottom', '80px')
					]),
				_List_fromArray(
					[
						function () {
						var _v0 = as_.Y;
						switch (_v0) {
							case 0:
								return $author$project$Main$viewScanTab(as_);
							case 1:
								return $author$project$Main$viewAddTab(as_);
							case 2:
								return $author$project$Main$viewLedgerTab(as_);
							case 3:
								return $author$project$Main$viewStatsTab(as_);
							default:
								return A3($author$project$Main$viewSettingsPanel, as_.c, true, as_.ac);
						}
					}()
					])),
				$author$project$Main$viewBottomNav(as_.Y),
				$author$project$Main$viewToast(as_.aV)
			]));
};
var $author$project$Main$SignInClicked = {$: 1};
var $author$project$Main$ToggleGuestSettings = {$: 2};
var $author$project$Main$guestMessage = function (reason) {
	switch (reason) {
		case 0:
			return $elm$core$Maybe$Nothing;
		case 1:
			return $elm$core$Maybe$Just('Session expired — tap Sign In to continue.');
		default:
			return $elm$core$Maybe$Just('Enter your Google Client ID in Settings first.');
	}
};
var $elm$html$Html$h1 = _VirtualDom_node('h1');
var $author$project$Main$viewGuest = function (gs) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'display', 'flex'),
				A2($elm$html$Html$Attributes$style, 'flex-direction', 'column'),
				A2($elm$html$Html$Attributes$style, 'align-items', 'center'),
				A2($elm$html$Html$Attributes$style, 'justify-content', 'center'),
				A2($elm$html$Html$Attributes$style, 'min-height', '100vh'),
				A2($elm$html$Html$Attributes$style, 'padding', '32px 24px'),
				A2($elm$html$Html$Attributes$style, 'text-align', 'center')
			]),
		_List_fromArray(
			[
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'font-size', '48px'),
						A2($elm$html$Html$Attributes$style, 'margin-bottom', '16px')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('🏔')
					])),
				A2(
				$elm$html$Html$h1,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'font-size', '32px'),
						A2($elm$html$Html$Attributes$style, 'font-weight', '700'),
						A2($elm$html$Html$Attributes$style, 'color', '#e8a020'),
						A2($elm$html$Html$Attributes$style, 'letter-spacing', '0.05em'),
						A2($elm$html$Html$Attributes$style, 'margin-bottom', '8px')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('ALASKA TRACKER')
					])),
				A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'color', '#7a8a80'),
						A2($elm$html$Html$Attributes$style, 'margin-bottom', '24px'),
						A2($elm$html$Html$Attributes$style, 'font-size', '16px')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('Road log for the long way north')
					])),
				function () {
				var _v0 = $author$project$Main$guestMessage(gs.s.aI);
				if (!_v0.$) {
					var msg = _v0.a;
					return A2(
						$elm$html$Html$div,
						_List_fromArray(
							[
								$elm$html$Html$Attributes$class('w-full mb-4 px-4 py-3 rounded-lg bg-[#2a1510] border border-[#e85030] text-[#e8a020] text-sm text-left')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text(msg)
							]));
				} else {
					return $elm$html$Html$text('');
				}
			}(),
				A2(
				$elm$html$Html$button,
				_List_fromArray(
					[
						$elm$html$Html$Events$onClick($author$project$Main$SignInClicked),
						A2($elm$html$Html$Attributes$style, 'background', '#e8a020'),
						A2($elm$html$Html$Attributes$style, 'color', '#0d0f0e'),
						A2($elm$html$Html$Attributes$style, 'border', 'none'),
						A2($elm$html$Html$Attributes$style, 'border-radius', '8px'),
						A2($elm$html$Html$Attributes$style, 'padding', '16px 32px'),
						A2($elm$html$Html$Attributes$style, 'font-size', '16px'),
						A2($elm$html$Html$Attributes$style, 'font-weight', '700'),
						A2($elm$html$Html$Attributes$style, 'cursor', 'pointer'),
						A2($elm$html$Html$Attributes$style, 'letter-spacing', '0.05em'),
						A2($elm$html$Html$Attributes$style, 'min-height', '52px')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('SIGN IN WITH GOOGLE')
					])),
				A2(
				$elm$html$Html$p,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'color', '#4a5a50'),
						A2($elm$html$Html$Attributes$style, 'margin-top', '24px'),
						A2($elm$html$Html$Attributes$style, 'font-size', '13px')
					]),
				_List_fromArray(
					[
						$elm$html$Html$text('Need a Google Client ID? Enter it in Settings below.')
					])),
				A2(
				$elm$html$Html$div,
				_List_fromArray(
					[
						A2($elm$html$Html$Attributes$style, 'margin-top', '48px'),
						A2($elm$html$Html$Attributes$style, 'width', '100%')
					]),
				_List_fromArray(
					[
						A2(
						$elm$html$Html$button,
						_List_fromArray(
							[
								$elm$html$Html$Events$onClick($author$project$Main$ToggleGuestSettings),
								A2($elm$html$Html$Attributes$style, 'background', 'none'),
								A2($elm$html$Html$Attributes$style, 'border', '1px solid #3a4240'),
								A2($elm$html$Html$Attributes$style, 'color', '#7a8a80'),
								A2($elm$html$Html$Attributes$style, 'border-radius', '6px'),
								A2($elm$html$Html$Attributes$style, 'padding', '10px 20px'),
								A2($elm$html$Html$Attributes$style, 'font-size', '14px'),
								A2($elm$html$Html$Attributes$style, 'cursor', 'pointer')
							]),
						_List_fromArray(
							[
								$elm$html$Html$text('⚙ Settings')
							])),
						gs.aC ? A3($author$project$Main$viewSettingsPanel, gs.s.c, false, gs.ac) : $elm$html$Html$text('')
					]))
			]));
};
var $author$project$Main$view = function (model) {
	return A2(
		$elm$html$Html$div,
		_List_fromArray(
			[
				A2($elm$html$Html$Attributes$style, 'background', '#0d0f0e'),
				A2($elm$html$Html$Attributes$style, 'color', '#c8d0c8'),
				A2($elm$html$Html$Attributes$style, 'min-height', '100vh'),
				A2($elm$html$Html$Attributes$style, 'font-family', '\'Barlow Condensed\', system-ui, sans-serif'),
				A2($elm$html$Html$Attributes$style, 'max-width', '480px'),
				A2($elm$html$Html$Attributes$style, 'margin', '0 auto'),
				A2($elm$html$Html$Attributes$style, 'position', 'relative')
			]),
		_List_fromArray(
			[
				function () {
				if (!model.$) {
					var gs = model.a;
					return $author$project$Main$viewGuest(gs);
				} else {
					var as_ = model.a;
					return $author$project$Main$viewAuth(as_);
				}
			}()
			]));
};
var $author$project$Main$main = $elm$browser$Browser$element(
	{
		dy: $author$project$Main$init,
		dX: function (_v0) {
			return $elm$core$Platform$Sub$batch(
				_List_fromArray(
					[
						$author$project$Main$gotNewToken($author$project$Main$GotOAuthToken),
						$author$project$Main$gotGpsCoords(
						function (r) {
							return r.ci ? $author$project$Main$GeolocationDenied : A2($author$project$Main$GotGpsCoords, r.M, r.P);
						}),
						$author$project$Main$gotExifResult(
						function (r) {
							return r.cp ? A4(
								$author$project$Main$GotExifCoords,
								r.E,
								$elm$core$Maybe$Just(r.M),
								$elm$core$Maybe$Just(r.P),
								'') : A4($author$project$Main$GotExifCoords, r.E, $elm$core$Maybe$Nothing, $elm$core$Maybe$Nothing, r.ch);
						})
					]));
		},
		d9: $author$project$Main$update,
		ea: $author$project$Main$view
	});
_Platform_export({'Main':{'init':$author$project$Main$main($elm$json$Json$Decode$value)(0)}});}(this));